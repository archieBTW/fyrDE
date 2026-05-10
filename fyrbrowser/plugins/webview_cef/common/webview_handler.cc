// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "webview_handler.h"

#include <sstream>
#include <string>
#include <iostream>
#include <chrono>
#include <unordered_map>
#include <cstdint>
#include <cstdlib>

#include "include/base/cef_callback.h"
#include "include/cef_app.h"
#include "include/cef_parser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"
#include "include/cef_request.h"

#include <sstream>

// std::to_string fails for ints on Ubuntu 24.04:
// webview_handler.cc:86:86: error: no matching function for call to 'to_string'
// webview_handler.cc:567:24: error: no matching function for call to 'to_string'
namespace stringpatch
{
    template < typename T > std::string to_string( const T& n )
    {
        std::ostringstream stm ;
        stm << n ;
        return stm.str() ;
    }
}

#include "webview_js_handler.h"

// namespace

// Returns a data: URI with the specified contents.
std::string GetDataURI(const std::string& data, const std::string& mime_type) {
    return "data:" + mime_type + ";base64," +
    CefURIEncode(CefBase64Encode(data.data(), data.size()), false)
        .ToString();
}



WebviewHandler::WebviewHandler() {

}

WebviewHandler::~WebviewHandler() {
    browser_map_.clear();
    js_callbacks_.clear();
}

bool WebviewHandler::OnProcessMessageReceived(
    CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
     CefProcessId source_process, CefRefPtr<CefProcessMessage> message)
{
	std::string message_name = message->GetName();
    if (message_name == kFocusedNodeChangedMessage)
    {
        bool editable = message->GetArgumentList()->GetBool(0);
        onFocusedNodeChangeMessage(browser->GetIdentifier(), editable);
        if (editable) {
            onImeCompositionRangeChangedMessage(browser->GetIdentifier(), message->GetArgumentList()->GetInt(1), message->GetArgumentList()->GetInt(2));
        }
    }
    else if(message_name == kJSCallCppFunctionMessage)
    {
        CefString fun_name = message->GetArgumentList()->GetString(0);
		CefString param = message->GetArgumentList()->GetString(1);
		int js_callback_id = message->GetArgumentList()->GetInt(2);

        if (fun_name.empty() || !(browser.get())) {
		    return false;
	    }

        onJavaScriptChannelMessage(
            fun_name,param,stringpatch::to_string(js_callback_id), browser->GetIdentifier(), stringpatch::to_string(frame->GetIdentifier()));
    }
    else if(message_name == kEvaluateCallbackMessage){
        CefString callbackId = message->GetArgumentList()->GetString(0);
        CefRefPtr<CefValue> param = message->GetArgumentList()->GetValue(1);

        if(!callbackId.empty()){
            std::lock_guard<std::recursive_mutex> lock(m_mutex);
            auto it = js_callbacks_.find(callbackId.ToString());
            if(it != js_callbacks_.end()){
                it->second(param);
                js_callbacks_.erase(it);
            }
        }
    }
    return false;
}

void WebviewHandler::OnTitleChange(CefRefPtr<CefBrowser> browser,
                                  const CefString& title) {
    //todo: title change
    if(onTitleChangedEvent) {
        onTitleChangedEvent(browser->GetIdentifier(), title);
    }
}

void WebviewHandler::OnAddressChange(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame,
                     const CefString& url) {
    if(onUrlChangedEvent) {
        onUrlChangedEvent(browser->GetIdentifier(), url);
    }
}

bool WebviewHandler::OnCursorChange(CefRefPtr<CefBrowser> browser,
                            CefCursorHandle cursor,
                            cef_cursor_type_t type,
                            const CefCursorInfo& custom_cursor_info){
    if(onCursorChangedEvent) {
        onCursorChangedEvent(browser->GetIdentifier(), type);
        return true;
    }
    return false;
}

bool WebviewHandler::OnTooltip(CefRefPtr<CefBrowser> browser, CefString& text) {
    if(onTooltipEvent) {
        onTooltipEvent(browser->GetIdentifier(), text);
        return true;
    }
    return false;
}

bool WebviewHandler::OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                      cef_log_severity_t level,
                                      const CefString& message,
                                      const CefString& source,
                                      int line){
    if(onConsoleMessageEvent){
        onConsoleMessageEvent(browser->GetIdentifier(), level, message, source, line);
    }
    return false;
}

void WebviewHandler::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    browser_map_.emplace(browser->GetIdentifier(), browser_info());
    browser_map_[browser->GetIdentifier()].browser = browser;
    
    if (browser->IsPopup()) {
        // Set a default size for popups so they can render before being resized by the UI
        browser_map_[browser->GetIdentifier()].width = 1280;
        browser_map_[browser->GetIdentifier()].height = 720;
        
        if (onPopupCreated) {
            onPopupCreated(browser->GetIdentifier());
        }
    }
}

bool WebviewHandler::DoClose(CefRefPtr<CefBrowser> browser) {
    CEF_REQUIRE_UI_THREAD();    
    if (onBrowserClose) {
        onBrowserClose(browser->GetIdentifier());
    }
    // Allow the close. For windowed browsers this will result in the OS close
    // event being sent.
    return false;
}

void WebviewHandler::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    browser_map_.erase(browser->GetIdentifier());
}

bool WebviewHandler::OnBeforePopup(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefFrame> frame,
                                  const CefString& target_url,
                                  const CefString& target_frame_name,
                                  WindowOpenDisposition target_disposition,
                                  bool user_gesture,
                                  const CefPopupFeatures& popupFeatures,
                                  CefWindowInfo& windowInfo,
                                  CefRefPtr<CefClient>& client,
                                  CefBrowserSettings& settings,
                                  CefRefPtr<CefDictionaryValue>& extra_info,
                                  bool* no_javascript_access) {
    if (onBeforePopup) {
        std::string url = target_url.ToString();
        if (url.empty()) url = "about:blank";
        onBeforePopup(browser->GetIdentifier(), url);
    }
    
    // Set as offscreen to allow FyrBrowser to render it
    windowInfo.SetAsWindowless(0);
    
    return false; // Return false to allow CEF to create the popup
}

void WebviewHandler::OnTakeFocus(CefRefPtr<CefBrowser> browser, bool next)
{
    executeJavaScript(browser->GetIdentifier(), "document.activeElement.blur()");
}

bool WebviewHandler::OnSetFocus(CefRefPtr<CefBrowser> browser, FocusSource source)
{
    return false;
}

void WebviewHandler::OnGotFocus(CefRefPtr<CefBrowser> browser)
{
}

void WebviewHandler::OnLoadError(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                ErrorCode errorCode,
                                const CefString& errorText,
                                const CefString& failedUrl) {
    CEF_REQUIRE_UI_THREAD();
    
    // Allow Chrome to show the error page.
    if (IsChromeRuntimeEnabled())
        return;
    
    // Don't display an error for downloaded files.
    if (errorCode == ERR_ABORTED)
        return;
    
    // Display a load error message using a data: URI.
    std::stringstream ss;
    ss << "<html><head><style>"
          "body { background-color: black; color: white; font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; text-align: center; overflow: hidden; }"
          ".container { max-width: 600px; animation: fadeIn 0.8s ease-out; }"
          "@keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }"
          "img { max-width: 150px; height: auto; margin-bottom: 30px; filter: drop-shadow(0 0 20px rgba(157, 80, 187, 0.4)); }"
          "h1 { font-size: 2.2rem; margin-bottom: 10px; background: linear-gradient(45deg, #9d50bb, #6e48aa); -webkit-background-clip: text; -webkit-text-fill-color: transparent; font-weight: 700; }"
          "p { font-size: 1.1rem; opacity: 0.7; line-height: 1.5; margin-bottom: 25px; }"
          ".url { color: #9d50bb; font-family: monospace; word-break: break-all; margin-top: 20px; font-size: 0.85rem; padding: 10px; background: rgba(157, 80, 187, 0.1); border-radius: 8px; border: 1px solid rgba(157, 80, 187, 0.2); }"
          ".button { margin-top: 40px; display: inline-block; padding: 12px 35px; background: linear-gradient(45deg, #9d50bb, #6e48aa); border: none; border-radius: 30px; color: white; font-weight: 600; cursor: pointer; text-decoration: none; transition: all 0.3s ease; box-shadow: 0 4px 15px rgba(157, 80, 187, 0.3); }"
          ".button:hover { transform: scale(1.05); box-shadow: 0 6px 20px rgba(157, 80, 187, 0.5); }"
          "</style></head><body><div class='container'>"
          "<img src='data:image/png;base64,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' alt='Fyr Icon'>"
          "<h1>Unable to Connect</h1>"
          "<p>We're having trouble reaching this site. Please check your internet connection or verify the URL is correct.</p>"
          "<div class='url'>" << failedUrl.ToString() << "</div>"
          "<a href='javascript:location.reload()' class='button'>Try Again</a>"
          "</div></body></html>";
    
    frame->LoadURL(GetDataURI(ss.str(), "text/html"));
}

void WebviewHandler::OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                 CefLoadHandler::TransitionType transition_type) {
    if(onLoadStart){
        onLoadStart(browser->GetIdentifier(), frame->GetURL());
    }
    return;
}

void WebviewHandler::OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                               int httpStatusCode) {
    if(onLoadEnd){
        onLoadEnd(browser->GetIdentifier(), frame->GetURL());
    }
    return;
}

void WebviewHandler::CloseAllBrowsers(bool force_close) {
    if (browser_map_.empty()){
        return;
    }
    
    for (auto& it : browser_map_){
        it.second.browser->GetHost()->CloseBrowser(force_close);
        it.second.browser = nullptr;
    }
    browser_map_.clear();
}

// static
bool WebviewHandler::IsChromeRuntimeEnabled() {
    static int value = -1;
    if (value == -1) {
        CefRefPtr<CefCommandLine> command_line =
        CefCommandLine::GetGlobalCommandLine();
        value = command_line->HasSwitch("enable-chrome-runtime") ? 1 : 0;
    }
    return value == 1;
}

void WebviewHandler::closeBrowser(int browserId)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if(it != browser_map_.end()){
        it->second.browser->GetHost()->CloseBrowser(true);
        it->second.browser = nullptr;
        browser_map_.erase(it);
    }
}

void WebviewHandler::createBrowser(std::string url, std::function<void(int)> callback)
{
#ifndef OS_MAC
    if(!CefCurrentlyOn(TID_UI)) {
		CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::createBrowser, this, url, callback));
		return;
	}
#endif
    CefBrowserSettings browser_settings ;
    browser_settings.windowless_frame_rate = 60;

    CefWindowInfo window_info;
    window_info.SetAsWindowless(0);
    callback(CefBrowserHost::CreateBrowserSync(window_info, this, url, browser_settings, nullptr, nullptr)->GetIdentifier());
}

void WebviewHandler::sendScrollEvent(int browserId, int x, int y, int deltaX, int deltaY) {
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;

#ifndef __APPLE__
        // The scrolling direction on Windows and Linux is different from MacOS
        deltaY = -deltaY;
        // Flutter scrolls too slowly, but we now handle smoothing in the Dart layer.
        it->second.browser->GetHost()->SendMouseWheelEvent(ev, deltaX, deltaY);


#else
        it->second.browser->GetHost()->SendMouseWheelEvent(ev, deltaX, deltaY);
#endif


    }
}

void WebviewHandler::changeSize(int browserId, float a_dpi, int w, int h)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.dpi = a_dpi;
        it->second.width = w;
        it->second.height = h;
        it->second.browser->GetHost()->WasResized();
    }
}

void WebviewHandler::cursorClick(int browserId, int x, int y, bool up, int button)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        
        CefBrowserHost::MouseButtonType btnType = MBT_LEFT;
        if (button == 1) btnType = MBT_MIDDLE;
        else if (button == 2) btnType = MBT_RIGHT;

        ev.modifiers = (btnType == MBT_LEFT) ? EVENTFLAG_LEFT_MOUSE_BUTTON : 
                       ((btnType == MBT_RIGHT) ? EVENTFLAG_RIGHT_MOUSE_BUTTON : EVENTFLAG_MIDDLE_MOUSE_BUTTON);

        if(up && it->second.is_dragging) {
            it->second.browser->GetHost()->DragTargetDrop(ev);
            it->second.browser->GetHost()->DragSourceSystemDragEnded();
            it->second.is_dragging = false;
        } else {
            it->second.browser->GetHost()->SendMouseClickEvent(ev, btnType, up, 1);
        }
    }
}

void WebviewHandler::cursorMove(int browserId, int x , int y, bool dragging)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        if(dragging) {
            ev.modifiers = EVENTFLAG_LEFT_MOUSE_BUTTON;
        }
        if(it->second.is_dragging && dragging) {
            it->second.browser->GetHost()->DragTargetDragOver(ev, DRAG_OPERATION_EVERY);
        } else {
            it->second.browser->GetHost()->SendMouseMoveEvent(ev, false);
        }
    }
}

bool WebviewHandler::StartDragging(CefRefPtr<CefBrowser> browser,
                                  CefRefPtr<CefDragData> drag_data,
                                  DragOperationsMask allowed_ops,
                                  int x,
                                  int y){
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browser->GetIdentifier());
    if (it != browser_map_.end() && it->second.browser->IsSame(browser)) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        ev.modifiers = EVENTFLAG_LEFT_MOUSE_BUTTON;
        it->second.browser->GetHost()->DragTargetDragEnter(drag_data, ev, DRAG_OPERATION_EVERY);
        it->second.is_dragging = true;
    }
    return true;
}

void WebviewHandler::OnImeCompositionRangeChanged(CefRefPtr<CefBrowser> browser, const CefRange &selection_range, const CefRenderHandler::RectList &character_bounds)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browser->GetIdentifier());
    if(it == browser_map_.end() || !it->second.browser.get() || browser->IsPopup()) {
        return;
    }
    if (!character_bounds.empty()) {
        if (it->second.is_ime_commit) {
            auto lastCharacter = character_bounds.back();
            it->second.prev_ime_position = lastCharacter;
            onImeCompositionRangeChangedMessage(browser->GetIdentifier(), lastCharacter.x + lastCharacter.width, lastCharacter.y + lastCharacter.height);
            it->second.is_ime_commit = false;
        }
        else
        {
            auto firstCharacter = character_bounds.front();
            if (firstCharacter != it->second.prev_ime_position) {
                it->second.prev_ime_position = firstCharacter;
                onImeCompositionRangeChangedMessage(browser->GetIdentifier(), firstCharacter.x, firstCharacter.y + firstCharacter.height);
            }
        }
    }
}

void WebviewHandler::sendKeyEvent(int browserId, CefKeyEvent& ev)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->GetHost()->SendKeyEvent(ev);
    }
}

void WebviewHandler::loadUrl(int browserId, std::string url)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->LoadURL(url);
    }
}

void WebviewHandler::goForward(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->GoForward();
    }
}

void WebviewHandler::goBack(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->GoBack();
    }
}

void WebviewHandler::reload(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        it->second.browser->GetMainFrame()->GetBrowser()->Reload();
    }
}

void WebviewHandler::openDevTools(int browserId) {
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end()) {
        CefWindowInfo windowInfo;
#ifdef OS_WIN
        windowInfo.SetAsPopup(nullptr, "DevTools");
#endif
        it->second.browser->GetHost()->ShowDevTools(windowInfo, this, CefBrowserSettings(), CefPoint());
    }
}

void WebviewHandler::imeSetComposition(int browserId, std::string text)
{
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }

    CefString cTextStr = CefString(text);

    std::vector<CefCompositionUnderline> underlines;
    cef_composition_underline_t underline = {};
    underline.range.from = 0;
    underline.range.to = static_cast<int>(0 + cTextStr.length());
    underline.color = ColorUNDERLINE;
    underline.background_color = ColorBKCOLOR;
    underline.thick = 0;
    underline.style = CEF_CUS_DOT;
    underlines.push_back(underline);

    // Keeps the caret at the end of the composition
    auto selection_range_end = static_cast<int>(0 + cTextStr.length());
    CefRange selection_range = CefRange(0, selection_range_end);
    it->second.browser->GetHost()->ImeSetComposition(cTextStr, underlines, CefRange(UINT32_MAX, UINT32_MAX), selection_range);
}

void WebviewHandler::imeCommitText(int browserId, std::string text)
{
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }

    CefString cTextStr = CefString(text);
    it->second.is_ime_commit = true;

    std::vector<CefCompositionUnderline> underlines;
    auto selection_range_end = static_cast<int>(0 + cTextStr.length());
    CefRange selection_range = CefRange(selection_range_end, selection_range_end);
#ifndef _WIN32
        it->second.browser->GetHost()->ImeSetComposition(cTextStr, underlines, CefRange(UINT32_MAX, UINT32_MAX), selection_range);
#endif
    it->second.browser->GetHost()->ImeCommitText(cTextStr, CefRange(UINT32_MAX, UINT32_MAX), 0);

}

void WebviewHandler::setClientFocus(int browserId, bool focus)
{
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it==browser_map_.end() || !it->second.browser.get()) {
        return;
    }
    it->second.browser->GetHost()->SetFocus(focus);
}

void WebviewHandler::setCookie(const std::string& domain, const std::string& key, const std::string& value){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if(manager){
        CefCookie cookie;
		CefString(&cookie.path).FromASCII("/");
		CefString(&cookie.name).FromString(key.c_str());
		CefString(&cookie.value).FromString(value.c_str());

		if (!domain.empty()) {
			CefString(&cookie.domain).FromString(domain.c_str());
		}

		cookie.httponly = true;
		cookie.secure = false;
		std::string httpDomain = "https://" + domain + "/cookiestorage";
		manager->SetCookie(httpDomain, cookie, nullptr);
    }
}

void WebviewHandler::deleteCookie(const std::string& domain, const std::string& key)
{
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (manager) {
        std::string httpDomain = "https://" + domain + "/cookiestorage";
        manager->DeleteCookies(httpDomain, key, nullptr);
    }
}

void WebviewHandler::visitAllCookies(std::function<void(std::map<std::string, std::map<std::string, std::string>>)> callback){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (!manager)
	{
		return;
	}

    CefRefPtr<WebviewCookieVisitor> cookieVisitor = new WebviewCookieVisitor();
    cookieVisitor->setOnVisitComplete(callback);

    manager->VisitAllCookies(cookieVisitor);
}

void WebviewHandler::visitUrlCookies(const std::string& domain, const bool& isHttpOnly, std::function<void(std::map<std::string, std::map<std::string, std::string>>)> callback){
    CefRefPtr<CefCookieManager> manager = CefCookieManager::GetGlobalManager(nullptr);
    if (!manager)
	{
		return;
	}

    CefRefPtr<WebviewCookieVisitor> cookieVisitor = new WebviewCookieVisitor();
    cookieVisitor->setOnVisitComplete(callback);

    std::string httpDomain = "https://" + domain + "/cookiestorage";

    manager->VisitUrlCookies(httpDomain, isHttpOnly, cookieVisitor);
}

void WebviewHandler::setJavaScriptChannels(int browserId, const std::vector<std::string> channels)
{
    std::string extensionCode = "try{";
    for(auto& channel : channels)
    {
        extensionCode += channel;
        extensionCode += " = (e,r) => {external.JavaScriptChannel('";
        extensionCode += channel;
        extensionCode += "',e,r)};";
    }
    extensionCode += "}catch(e){console.log(e);}";
    executeJavaScript(browserId, extensionCode);
}

void WebviewHandler::sendJavaScriptChannelCallBack(const bool error, const std::string result, const std::string callbackId, const int browserId, const std::string frameId)
{
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kExecuteJsCallbackMessage);
    CefRefPtr<CefListValue> args = message->GetArgumentList();
    args->SetInt(0, atoi(callbackId.c_str()));
    args->SetBool(1, error);
    args->SetString(2, result);
    auto bit = browser_map_.find(browserId);
    if(bit != browser_map_.end()){
        int64_t frameIdInt = atoll(frameId.c_str());

        CefRefPtr<CefFrame> frame = bit->second.browser->GetMainFrame();

        // Return types for frame->GetIdentifier() changed, use the Linux way when updating MacOS or Windows
        // versions in download.cmake
#if __linux__
        bool identifierMatch = std::stoll(frame->GetIdentifier().ToString()) == frameIdInt;
#else
        bool identifierMatch = frame->GetIdentifier() == frameIdInt;
#endif
        if (identifierMatch)
        {
            frame->SendProcessMessage(PID_RENDERER, message);
        }
    }
}

static std::string GetCallbackId()
{
    auto time = std::chrono::time_point_cast<std::chrono::nanoseconds>(std::chrono::system_clock::now());
	time_t timestamp = time.time_since_epoch().count();
    return std::to_string(timestamp);
} 

void WebviewHandler::executeJavaScript(int browserId, const std::string code, std::function<void(CefRefPtr<CefValue>)> callback)
{
    if(!code.empty())
    {
        auto bit = browser_map_.find(browserId);
        if(bit != browser_map_.end() && bit->second.browser.get()){
            CefRefPtr<CefFrame> frame = bit->second.browser->GetMainFrame();
            if (frame)
            {
                std::string finalCode = code;
                if(callback != nullptr){
                    std::string callbackId = GetCallbackId();

                    finalCode = "external.EvaluateCallback('";
                    finalCode += callbackId;
                    finalCode += "',(function(){return ";
                    finalCode += code;
                    finalCode += "})());";
                    js_callbacks_[callbackId] = callback;
                }
			    frame->ExecuteJavaScript(finalCode, frame->GetURL(), 0);
            }
        }
    }
}

void WebviewHandler::GetViewRect(CefRefPtr<CefBrowser> browser, CefRect &rect) {
    CEF_REQUIRE_UI_THREAD();
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browser->GetIdentifier());
    if(it == browser_map_.end() || !it->second.browser.get()) {
        return;
    }
    rect.x = rect.y = 0;
    
    if (it->second.width < 1) {
        rect.width = 1;
    } else {
        rect.width = it->second.width;
    }
    
    if (it->second.height < 1) {
        rect.height = 1;
    } else {
        rect.height = it->second.height;
    }
}

bool WebviewHandler::GetScreenInfo(CefRefPtr<CefBrowser> browser, CefScreenInfo& screen_info) {
    //todo: hi dpi support
    screen_info.device_scale_factor  = browser_map_[browser->GetIdentifier()].dpi;
    return false;
}

void WebviewHandler::OnPaint(CefRefPtr<CefBrowser> browser, CefRenderHandler::PaintElementType type,
                            const CefRenderHandler::RectList &dirtyRects, const void *buffer, int w, int h) {
    if (!browser->IsPopup() && onPaintCallback != nullptr) {
        onPaintCallback(browser->GetIdentifier(), buffer, w, h);
    }
}


bool WebviewHandler::OnBeforeDownload(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefDownloadItem> download_item,
    const CefString& suggested_name,
    CefRefPtr<CefBeforeDownloadCallback> callback) {
  CEF_REQUIRE_UI_THREAD();
  
  if (onDownloadStart) {
    onDownloadStart(browser->GetIdentifier(), suggested_name.ToString(), download_item->GetURL().ToString());
  }
  
  // Construction of the download path (e.g., ~/Downloads/filename)
  char* home = getenv("HOME");
  std::string download_path;
  if (home != nullptr) {
    download_path = std::string(home) + "/Downloads/" + suggested_name.ToString();
  } else {
    download_path = "/tmp/" + suggested_name.ToString();
  }
  
  // Continue the download without showing the "Save As" dialog.
  callback->Continue(download_path, false);
  return true;
}

void WebviewHandler::OnDownloadUpdated(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefDownloadItem> download_item,
    CefRefPtr<CefDownloadItemCallback> callback) {
  CEF_REQUIRE_UI_THREAD();
  
  if (onDownloadUpdated) {
    onDownloadUpdated(
        browser->GetIdentifier(),
        download_item->GetURL().ToString(),
        download_item->GetReceivedBytes(),
        download_item->GetTotalBytes(),
        download_item->GetPercentComplete(),
        download_item->IsComplete());
  }
}

void WebviewHandler::OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                                 CefRefPtr<CefFrame> frame,
                                 CefRefPtr<CefContextMenuParams> params,
                                 CefRefPtr<CefMenuModel> model) {
    CEF_REQUIRE_UI_THREAD();
    // Clear the default menu
    model->Clear();
    
    if (onContextMenu) {
        onContextMenu(
            browser->GetIdentifier(),
            params->GetXCoord(),
            params->GetYCoord(),
            params->GetTypeFlags(),
            params->GetLinkUrl().ToString(),
            params->GetSourceUrl().ToString(),
            params->GetSelectionText().ToString(),
            params->IsEditable()
        );
    }
}

bool WebviewHandler::OnShowPermissionPrompt(
    CefRefPtr<CefBrowser> browser,
    uint64_t prompt_id,
    const CefString& requesting_origin,
    uint32_t prompt_flags,
    CefRefPtr<CefPermissionPromptCallback> callback) {
  CEF_REQUIRE_UI_THREAD();
  
  std::cerr << "!!!!! FyrBrowser [Permission] Origin: " << requesting_origin.ToString() 
            << " requested prompt flags: " << prompt_flags << " - Auto-Accepting" << std::endl;
  
  // Auto-accept all permissions for a better integrated experience
  callback->Continue(CEF_PERMISSION_RESULT_ACCEPT);
  return true;
}

bool WebviewHandler::OnRequestMediaAccessPermission(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame,
    const CefString& requesting_origin,
    uint32_t prompt_flags,
    CefRefPtr<CefMediaAccessCallback> callback) {
  CEF_REQUIRE_UI_THREAD();

  std::cerr << "!!!!! FyrBrowser [MediaAccess] Origin: " << requesting_origin.ToString() 
            << " requested media flags: " << prompt_flags << " - Auto-Accepting" << std::endl;

  // Accept all requested types (audio/video capture, etc.)
  callback->Continue(prompt_flags);
  return true;
}

bool WebviewHandler::OnFileDialog(CefRefPtr<CefBrowser> browser,
                                 FileDialogMode mode,
                                 const CefString& title,
                                 const CefString& default_file_path,
                                 const std::vector<CefString>& accept_filters,
                                 const std::vector<CefString>& accept_extensions,
                                 const std::vector<CefString>& accept_descriptions,
                                 CefRefPtr<CefFileDialogCallback> callback) {
  CEF_REQUIRE_UI_THREAD();
  
  last_callback_id_++;
  file_dialog_callbacks_[last_callback_id_] = callback;
  
  if (onFileDialog) {
    onFileDialog(browser->GetIdentifier(), last_callback_id_);
  } else {
    // If no handler, cancel the dialog
    callback->Cancel();
    file_dialog_callbacks_.erase(last_callback_id_);
  }
  
  return true;
}

void WebviewHandler::continueFileDialog(int callbackId, const std::vector<std::string>& filePaths) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::continueFileDialog, this, callbackId, filePaths));
    return;
  }
  CEF_REQUIRE_UI_THREAD();
  
  auto it = file_dialog_callbacks_.find(callbackId);
  if (it != file_dialog_callbacks_.end()) {
    std::vector<CefString> cefPaths;
    for (const auto& path : filePaths) {
      cefPaths.push_back(path);
    }
    
    if (cefPaths.empty()) {
      it->second->Cancel();
    } else {
      it->second->Continue(cefPaths);
    }
    
    file_dialog_callbacks_.erase(it);
  }
}
bool WebviewHandler::OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                                   CefRefPtr<CefFrame> frame,
                                   CefRefPtr<CefRequest> request,
                                   bool user_gesture,
                                   bool is_redirect) {
  CEF_REQUIRE_UI_THREAD();
  
  std::string url = request->GetURL().ToString();
  size_t colon_pos = url.find(':');
  if (colon_pos != std::string::npos) {
    std::string scheme = url.substr(0, colon_pos);
    // Convert scheme to lowercase
    for (auto & c: scheme) c = tolower(c);
    
    // List of standard web schemes we handle internally
    if (scheme != "http" && scheme != "https" && scheme != "file" && 
        scheme != "data" && scheme != "blob" && scheme != "about" && 
        scheme != "chrome" && scheme != "chrome-extension") {
      
      // This is likely an external protocol (magnet, mailto, etc.)
      if (onExternalProtocol) {
        onExternalProtocol(browser->GetIdentifier(), url);
        return true; // Cancel the navigation in CEF
      }
    }
  }
  
  return false;
}
