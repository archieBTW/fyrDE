// Copyright (c) 2013 The Chromium Embedded Framework Authors. All rights
// reserved. Use of this source code is governed by a BSD-style license that
// can be found in the LICENSE file.

#include "webview_handler.h"

#include <algorithm>
#include <cctype>
#include <sstream>
#include <string>
#include <iostream>
#include <chrono>
#include <unordered_map>
#include <cstdint>
#include <cstdlib>
#ifndef _WIN32
#include <sys/stat.h>
#endif

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

static std::string ToLowerAscii(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return s;
}

static std::string ExtractLowerHost(const std::string& url) {
    if (url.empty()) return "";
    CefURLParts parts;
    if (!CefParseURL(url, parts)) return "";
    std::string host = ToLowerAscii(CefString(&parts.host).ToString());
    while (!host.empty() && host.back() == '.') {
        host.pop_back();
    }
    return host;
}

static bool HostMatchesDomain(const std::string& host, const std::string& domain) {
    if (host.empty() || domain.empty()) return false;
    if (host == domain) return true;
    if (host.size() > domain.size() + 1) {
        size_t offset = host.size() - domain.size();
        return host[offset - 1] == '.' && host.compare(offset, domain.size(), domain) == 0;
    }
    return false;
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
            std::function<void(CefRefPtr<CefValue>)> cb;
            {
                std::lock_guard<std::recursive_mutex> lock(m_mutex);
                auto it = js_callbacks_.find(callbackId.ToString());
                if(it != js_callbacks_.end()){
                    cb = std::move(it->second);
                    js_callbacks_.erase(it);
                }
            }
            if (cb) {
                cb(param);
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
    if (!frame || !frame->IsMain()) {
        return;
    }
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
    const int browserId = browser->GetIdentifier();
    const bool isPopup = browser->IsPopup();
    {
        std::lock_guard<std::recursive_mutex> lock(m_mutex);
        browser_map_.emplace(browserId, browser_info());
        browser_map_[browserId].browser = browser;

        if (isPopup) {
            // Set a default size for popups so they can render before being resized by the UI
            browser_map_[browserId].width = 1280;
            browser_map_[browserId].height = 720;
        }
    }

    // Invoke outside m_mutex to avoid AB-BA deadlocks with WebviewPlugin::m_mutex.
    if (isPopup && onPopupCreated) {
        onPopupCreated(browserId);
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
    {
        std::lock_guard<std::recursive_mutex> lock(m_mutex);
        browser_map_.erase(browser->GetIdentifier());
    }
    {
        std::lock_guard<std::mutex> lock(adblock_mutex_);
        adblock_counts_.erase(browser->GetIdentifier());
    }
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
    
    // Set as offscreen to allow FyrBrowser to render it with opaque default white canvas.
    settings.background_color = CefColorSetARGB(255, 255, 255, 255);
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

void WebviewHandler::OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                                          bool isLoading,
                                          bool canGoBack,
                                          bool canGoForward) {
    if (onLoadingStateChanged && browser) {
        onLoadingStateChanged(browser->GetIdentifier(), isLoading, canGoBack, canGoForward);
    }
}

void WebviewHandler::OnLoadError(CefRefPtr<CefBrowser> browser,
                                CefRefPtr<CefFrame> frame,
                                ErrorCode errorCode,
                                const CefString& errorText,
                                const CefString& failedUrl) {
    CEF_REQUIRE_UI_THREAD();

    if (IsChromeRuntimeEnabled())
        return;

    if (!frame || !frame->IsMain())
        return;

    // Don't display an error for downloaded files or canceled navigations.
    if (errorCode == ERR_ABORTED)
        return;

    if (onLoadError && browser) {
        onLoadError(
            browser->GetIdentifier(),
            static_cast<int>(errorCode),
            errorText.ToString(),
            failedUrl.ToString());
    }
}

void WebviewHandler::OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                 CefLoadHandler::TransitionType transition_type) {
    if (!frame || !frame->IsMain()) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(adblock_mutex_);
        adblock_counts_[browser->GetIdentifier()] = 0;
    }
    if (onAdBlocked) {
        onAdBlocked(browser->GetIdentifier(), 0);
    }
    if(onLoadStart){
        onLoadStart(browser->GetIdentifier(), frame->GetURL());
    }
}

void WebviewHandler::OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                               int httpStatusCode) {
    if (!frame || !frame->IsMain()) {
        return;
    }
    if(onLoadEnd){
        onLoadEnd(browser->GetIdentifier(), frame->GetURL());
    }
}

void WebviewHandler::CloseAllBrowsers(bool force_close) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::CloseAllBrowsers, this, force_close));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    if (browser_map_.empty()){
        return;
    }
    
    for (auto& it : browser_map_){
        if (it.second.browser) {
            it.second.browser->GetHost()->CloseBrowser(force_close);
            it.second.browser = nullptr;
        }
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
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::closeBrowser, this, browserId));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if(it != browser_map_.end()){
        if (it->second.browser) {
            it->second.browser->GetHost()->CloseBrowser(true);
            it->second.browser = nullptr;
        }
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
    browser_settings.background_color = CefColorSetARGB(255, 255, 255, 255);

    CefWindowInfo window_info;
    window_info.SetAsWindowless(0);
    callback(CefBrowserHost::CreateBrowserSync(window_info, this, url, browser_settings, nullptr, nullptr)->GetIdentifier());
}

void WebviewHandler::sendScrollEvent(int browserId, int x, int y, int deltaX, int deltaY) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::sendScrollEvent, this, browserId, x, y, deltaX, deltaY));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;

#ifndef __APPLE__
        deltaY = -deltaY;
        it->second.browser->GetHost()->SendMouseWheelEvent(ev, deltaX, deltaY);
#else
        it->second.browser->GetHost()->SendMouseWheelEvent(ev, deltaX, deltaY);
#endif
    }
}

void WebviewHandler::changeSize(int browserId, float a_dpi, int w, int h)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::changeSize, this, browserId, a_dpi, w, h));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser) {
        it->second.dpi = a_dpi;
        it->second.width = w;
        it->second.height = h;
        it->second.browser->GetHost()->WasResized();
    }
}

void WebviewHandler::cursorClick(int browserId, int x, int y, bool up, int button)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::cursorClick, this, browserId, x, y, up, button));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser) {
        CefMouseEvent ev;
        ev.x = x;
        ev.y = y;
        
        CefBrowserHost::MouseButtonType btnType = MBT_LEFT;
        if (button == 1) btnType = MBT_MIDDLE;
        else if (button == 2) btnType = MBT_RIGHT;

        ev.modifiers = (btnType == MBT_LEFT) ? EVENTFLAG_LEFT_MOUSE_BUTTON : 
                       ((btnType == MBT_RIGHT) ? EVENTFLAG_RIGHT_MOUSE_BUTTON : EVENTFLAG_MIDDLE_MOUSE_BUTTON);

        if (!up && btnType == MBT_LEFT) {
            it->second.is_dragging = false;
        }

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
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::cursorMove, this, browserId, x, y, dragging));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser) {
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

void WebviewHandler::sendKeyEvent(int browserId, CefKeyEvent ev)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::sendKeyEvent, this, browserId, ev));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->GetHost()->SendKeyEvent(ev);
    }
}

void WebviewHandler::loadUrl(int browserId, std::string url)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::loadUrl, this, browserId, url));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->GetMainFrame()->LoadURL(url);
    }
}

void WebviewHandler::goForward(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::goForward, this, browserId));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->GoForward();
    }
}

void WebviewHandler::goBack(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::goBack, this, browserId));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->GoBack();
    }
}

void WebviewHandler::reload(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::reload, this, browserId));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->Reload();
    }
}

void WebviewHandler::stopLoad(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::stopLoad, this, browserId));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->StopLoad();
    }
}

void WebviewHandler::findInPage(int browserId, const std::string& searchText, bool forward, bool matchCase, bool findNext) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::findInPage, this, browserId, searchText, forward, matchCase, findNext));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->GetHost()->Find(searchText, forward, matchCase, findNext);
    }
}

void WebviewHandler::stopFinding(int browserId, bool clearSelection) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::stopFinding, this, browserId, clearSelection));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->GetHost()->StopFinding(clearSelection);
    }
}

void WebviewHandler::setZoomLevel(int browserId, double zoomLevel) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::setZoomLevel, this, browserId, zoomLevel));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        it->second.browser->GetHost()->SetZoomLevel(zoomLevel);
    }
}

void WebviewHandler::setAdBlockConfig(bool enabled, const std::vector<std::string>& blockedDomains, const std::vector<std::string>& whitelistHosts) {
    std::lock_guard<std::mutex> lock(adblock_mutex_);
    adblock_enabled_ = enabled;
    adblock_domains_.clear();
    for (const auto& d : blockedDomains) {
        if (!d.empty()) {
            adblock_domains_.insert(ToLowerAscii(d));
        }
    }
    adblock_whitelist_.clear();
    for (const auto& h : whitelistHosts) {
        if (!h.empty()) {
            adblock_whitelist_.insert(ToLowerAscii(h));
        }
    }
}

bool WebviewHandler::isHostInSet(const std::string& host, const std::unordered_set<std::string>& domainSet) const {
    if (host.empty() || domainSet.empty()) return false;
    for (const auto& domain : domainSet) {
        if (HostMatchesDomain(host, domain)) {
            return true;
        }
    }
    return false;
}

void WebviewHandler::openDevTools(int browserId) {
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::openDevTools, this, browserId));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browserId);
    if (it != browser_map_.end() && it->second.browser.get()) {
        CefWindowInfo windowInfo;
#ifdef OS_WIN
        windowInfo.SetAsPopup(nullptr, "DevTools");
#endif
        it->second.browser->GetHost()->ShowDevTools(windowInfo, this, CefBrowserSettings(), CefPoint());
    }
}

void WebviewHandler::imeSetComposition(int browserId, std::string text)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeSetComposition, this, browserId, text));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
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
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::imeCommitText, this, browserId, text));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
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
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::setClientFocus, this, browserId, focus));
        return;
    }
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
        extensionCode += "window." + channel + " = { postMessage: (e,r) => {external.JavaScriptChannel('";
        extensionCode += channel;
        extensionCode += "',e,r)} };";
    }
    extensionCode += "}catch(e){console.log(e);}";
    executeJavaScript(browserId, extensionCode);
}

void WebviewHandler::sendJavaScriptChannelCallBack(const bool error, const std::string result, const std::string callbackId, const int browserId, const std::string frameId)
{
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::sendJavaScriptChannelCallBack, this, error, result, callbackId, browserId, frameId));
        return;
    }
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create(kExecuteJsCallbackMessage);
    CefRefPtr<CefListValue> args = message->GetArgumentList();
    args->SetInt(0, atoi(callbackId.c_str()));
    args->SetBool(1, error);
    args->SetString(2, result);
    auto bit = browser_map_.find(browserId);
    if(bit != browser_map_.end() && bit->second.browser){
        int64_t frameIdInt = atoll(frameId.c_str());

        CefRefPtr<CefFrame> frame = bit->second.browser->GetMainFrame();

        // Return types for frame->GetIdentifier() changed, use the Linux way when updating MacOS or Windows
        // versions in download.cmake
#if __linux__
        bool identifierMatch = frame && std::stoll(frame->GetIdentifier().ToString()) == frameIdInt;
#else
        bool identifierMatch = frame && frame->GetIdentifier() == frameIdInt;
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
    if (!CefCurrentlyOn(TID_UI)) {
        CefPostTask(TID_UI, base::BindOnce(&WebviewHandler::executeJavaScript, this, browserId, code, callback));
        return;
    }
    if(!code.empty())
    {
        std::lock_guard<std::recursive_mutex> lock(m_mutex);
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
                return;
            }
        }
    }
    if (callback != nullptr) {
        callback(nullptr);
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
    CEF_REQUIRE_UI_THREAD();
    std::lock_guard<std::recursive_mutex> lock(m_mutex);
    auto it = browser_map_.find(browser->GetIdentifier());
    float dpi = 1.0f;
    int width = 1280;
    int height = 720;
    if (it != browser_map_.end()) {
        if (it->second.dpi > 0.0f) dpi = it->second.dpi;
        if (it->second.width > 1) width = static_cast<int>(it->second.width);
        if (it->second.height > 1) height = static_cast<int>(it->second.height);
    }
    screen_info.device_scale_factor = dpi;
    screen_info.depth = 24;
    screen_info.depth_per_component = 8;
    screen_info.is_monochrome = 0;
    screen_info.rect = CefRect(0, 0, width, height);
    screen_info.available_rect = CefRect(0, 0, width, height);
    return true;
}

void WebviewHandler::OnPaint(CefRefPtr<CefBrowser> browser, CefRenderHandler::PaintElementType type,
                            const CefRenderHandler::RectList &dirtyRects, const void *buffer, int w, int h) {
    if (onPaintCallback != nullptr) {
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
  std::string safe_name = suggested_name.ToString();
  size_t last_slash = safe_name.find_last_of("/\\");
  if (last_slash != std::string::npos) {
    safe_name = safe_name.substr(last_slash + 1);
  }
  if (safe_name.empty() || safe_name == "." || safe_name == "..") {
    safe_name = "download";
  }

  char* home = getenv("HOME");
  std::string download_path;
  if (home != nullptr) {
    std::string downloads_dir = std::string(home) + "/Downloads";
#ifndef _WIN32
    mkdir(downloads_dir.c_str(), 0755);
#endif
    download_path = downloads_dir + "/" + safe_name;
  } else {
    download_path = "/tmp/" + safe_name;
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

CefRefPtr<CefResourceRequestHandler> WebviewHandler::GetResourceRequestHandler(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame,
    CefRefPtr<CefRequest> request,
    bool is_navigation,
    bool is_download,
    const CefString& request_initiator,
    bool& disable_default_handling) {
  if (!request) {
    return nullptr;
  }
  if ((is_navigation && frame && frame->IsMain()) || request->GetResourceType() == RT_MAIN_FRAME) {
    return nullptr;
  }
  std::lock_guard<std::mutex> lock(adblock_mutex_);
  if (!adblock_enabled_ || adblock_domains_.empty()) {
    return nullptr;
  }
  return this;
}

CefResourceRequestHandler::ReturnValue WebviewHandler::OnBeforeResourceLoad(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame,
    CefRefPtr<CefRequest> request,
    CefRefPtr<CefCallback> callback) {
  if (!request || request->GetResourceType() == RT_MAIN_FRAME) {
    return RV_CONTINUE;
  }

  std::string req_host = ExtractLowerHost(request->GetURL().ToString());
  if (req_host.empty()) {
    return RV_CONTINUE;
  }

  std::string page_host;
  if (browser && browser->GetMainFrame()) {
    page_host = ExtractLowerHost(browser->GetMainFrame()->GetURL().ToString());
  }
  if (page_host.empty() && frame) {
    page_host = ExtractLowerHost(frame->GetURL().ToString());
  }
  if (page_host.empty()) {
    page_host = ExtractLowerHost(request->GetReferrerURL().ToString());
  }

  // Never block first-party subresources (including subdomains of the current site)
  if (!page_host.empty() && HostMatchesDomain(req_host, page_host)) {
    return RV_CONTINUE;
  }

  int blocked_count = -1;
  {
    std::lock_guard<std::mutex> lock(adblock_mutex_);
    if (!adblock_enabled_ || isHostInSet(page_host, adblock_whitelist_)) {
      return RV_CONTINUE;
    }
    if (isHostInSet(req_host, adblock_domains_)) {
      if (browser) {
        blocked_count = ++adblock_counts_[browser->GetIdentifier()];
      } else {
        blocked_count = 0;
      }
    }
  }

  if (blocked_count >= 0) {
    if (onAdBlocked && browser) {
      onAdBlocked(browser->GetIdentifier(), blocked_count);
    }
    return RV_CANCEL;
  }

  return RV_CONTINUE;
}

void WebviewHandler::OnFindResult(CefRefPtr<CefBrowser> browser,
                                  int identifier,
                                  int count,
                                  const CefRect& selectionRect,
                                  int activeMatchOrdinal,
                                  bool finalUpdate) {
  if (onFindResult && browser) {
    onFindResult(browser->GetIdentifier(), count, activeMatchOrdinal, finalUpdate);
  }
}
