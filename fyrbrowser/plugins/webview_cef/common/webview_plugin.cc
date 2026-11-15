#include "webview_plugin.h"

#ifdef OS_MAC
#include <include/wrapper/cef_library_loader.h>
#endif

#include <math.h>
#include <memory>
#include <thread>
#include <iostream>
#include <unordered_map>

namespace webview_cef {
	CefMainArgs mainArgs;
	CefRefPtr<WebviewApp> app;
	CefString userAgent;
	bool isCefInitialized = false;

	WebviewPlugin::WebviewPlugin() {
		m_handler = new WebviewHandler();
        }

    WebviewPlugin::~WebviewPlugin() {
		uninitCallback();
		m_handler->CloseAllBrowsers(true);
		m_handler = nullptr;
		if(!m_renderers.empty()){
			m_renderers.clear();
		}
	}

	void WebviewPlugin::initCallback() {
		if (!m_init)
		{
			m_handler->onPaintCallback = [=](int browserId, const void* buffer, int32_t width, int32_t height)
			{
				std::lock_guard<std::recursive_mutex> lock(m_mutex);
				if (m_renderers.count(browserId))
				{
					m_renderers[browserId]->onFrame(buffer, width, height);
				}
				else if (m_logFunc) {
					m_logFunc("onPaintCallback: No renderer for browserId " + std::to_string(browserId));
				}
			};

			m_handler->onTooltipEvent = [=](int browserId, std::string text) {
				if (m_invokeFunc) {
					WValue* bId = webview_value_new_int(browserId);
					WValue* wText = webview_value_new_string(const_cast<char*>(text.c_str()));
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "text", wText);
					m_invokeFunc("onTooltip", retMap);
					webview_value_unref(bId);
					webview_value_unref(wText);
					webview_value_unref(retMap);
				}
			};

			m_handler->onCursorChangedEvent = [=](int browserId, int type) {
				if(m_invokeFunc){
					WValue* bId = webview_value_new_int(browserId);
					WValue* wType = webview_value_new_int(type);
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "type", wType);
					m_invokeFunc("onCursorChanged", retMap);
					webview_value_unref(bId);
					webview_value_unref(wType);
					webview_value_unref(retMap);
				}
			};

			m_handler->onConsoleMessageEvent = [=](int browserId, int level, std::string message, std::string source, int line){
				if(m_invokeFunc){
					WValue* bId = webview_value_new_int(browserId);
					WValue* wLevel = webview_value_new_int(level);
					WValue* wMessage = webview_value_new_string(const_cast<char*>(message.c_str()));
					WValue* wSource = webview_value_new_string(const_cast<char*>(source.c_str()));
					WValue* wLine = webview_value_new_int(line);
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "level", wLevel);
					webview_value_set_string(retMap, "message", wMessage);
					webview_value_set_string(retMap, "source", wSource);
					webview_value_set_string(retMap, "line", wLine);
					m_invokeFunc("onConsoleMessage", retMap);
					webview_value_unref(bId);
					webview_value_unref(wLevel);
					webview_value_unref(wMessage);
					webview_value_unref(wSource);
					webview_value_unref(wLine);
					webview_value_unref(retMap);
				}
			};

			m_handler->onUrlChangedEvent = [=](int browserId, std::string url)
			{
				if (m_invokeFunc)
				{
					WValue* bId = webview_value_new_int(browserId);
					WValue* wUrl = webview_value_new_string(const_cast<char*>(url.c_str()));
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "url", wUrl);
					m_invokeFunc("urlChanged", retMap);
					webview_value_unref(bId);
					webview_value_unref(wUrl);
					webview_value_unref(retMap);
				}
			};

			m_handler->onTitleChangedEvent = [=](int browserId, std::string title)
			{
				if (m_invokeFunc)
				{
					WValue* bId = webview_value_new_int(browserId);
					WValue* wTitle = webview_value_new_string(const_cast<char*>(title.c_str()));
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "title", wTitle);
					m_invokeFunc("titleChanged", retMap);
					webview_value_unref(bId);
					webview_value_unref(wTitle);
					webview_value_unref(retMap);
				}
			};

			m_handler->onJavaScriptChannelMessage = [=](std::string channelName, std::string message, std::string callbackId, int browserId, std::string frameId)
			{
				if (m_invokeFunc)
				{
					WValue* retMap = webview_value_new_map();
					WValue* channel = webview_value_new_string(const_cast<char*>(channelName.c_str()));
					WValue* msg = webview_value_new_string(const_cast<char*>(message.c_str()));
					WValue* cbId = webview_value_new_string(const_cast<char*>(callbackId.c_str()));
					WValue* bId = webview_value_new_int(browserId);
					WValue* fId = webview_value_new_string(const_cast<char*>(frameId.c_str()));
					webview_value_set_string(retMap, "channel", channel);
					webview_value_set_string(retMap, "message", msg);
					webview_value_set_string(retMap, "callbackId", cbId);
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "frameId", fId);
					m_invokeFunc("javascriptChannelMessage", retMap);
					webview_value_unref(retMap);
					webview_value_unref(channel);
					webview_value_unref(msg);
					webview_value_unref(cbId);
					webview_value_unref(bId);
					webview_value_unref(fId);
				}
			};

			m_handler->onFocusedNodeChangeMessage = [=](int nBrowserId, bool bEditable)
			{
				if (m_invokeFunc)
				{
					WValue* bId = webview_value_new_int(int64_t(nBrowserId));
					WValue* editable = webview_value_new_bool(bEditable);
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "editable", editable);
					m_invokeFunc("onFocusedNodeChangeMessage", retMap);
					webview_value_unref(bId);
					webview_value_unref(editable);
					webview_value_unref(retMap);
				}
			};

			m_handler->onImeCompositionRangeChangedMessage = [=](int nBrowserId, int32_t x, int32_t y)
			{
				if (m_invokeFunc)
				{
					WValue* bId = webview_value_new_int(nBrowserId);
					WValue* retMap = webview_value_new_map();
					WValue* xValue = webview_value_new_int(x);
					WValue* yValue = webview_value_new_int(y);
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "x", xValue);
					webview_value_set_string(retMap, "y", yValue);
					m_invokeFunc("onImeCompositionRangeChangedMessage", retMap);
					webview_value_unref(bId);
					webview_value_unref(xValue);
					webview_value_unref(yValue);
					webview_value_unref(retMap);
				}
			};


            m_handler->onLoadStart = [=](int nBrowserId, std::string urlId)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(nBrowserId);
                    WValue* uId = webview_value_new_string(const_cast<char*>(urlId.c_str()));
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "urlId", uId);
                    m_invokeFunc("onLoadStart", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(uId);
                    webview_value_unref(retMap);
                }
            };

            m_handler->onLoadEnd = [=](int nBrowserId, std::string urlId)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(nBrowserId);
                    WValue* uId = webview_value_new_string(const_cast<char*>(urlId.c_str()));
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "urlId", uId);
                    m_invokeFunc("onLoadEnd", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(uId);
                    webview_value_unref(retMap);
                }
            };

            m_handler->onLoadError = [=](int nBrowserId, int errorCode, std::string errorText, std::string failedUrl)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(nBrowserId);
                    WValue* eCode = webview_value_new_int(errorCode);
                    WValue* eText = webview_value_new_string(const_cast<char*>(errorText.c_str()));
                    WValue* fUrl = webview_value_new_string(const_cast<char*>(failedUrl.c_str()));
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "errorCode", eCode);
                    webview_value_set_string(retMap, "errorText", eText);
                    webview_value_set_string(retMap, "failedUrl", fUrl);
                    m_invokeFunc("onLoadError", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(eCode);
                    webview_value_unref(eText);
                    webview_value_unref(fUrl);
                    webview_value_unref(retMap);
                }
            };

            m_handler->onLoadingStateChanged = [=](int nBrowserId, bool isLoading, bool canGoBack, bool canGoForward)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(nBrowserId);
                    WValue* wLoading = webview_value_new_bool(isLoading);
                    WValue* wBack = webview_value_new_bool(canGoBack);
                    WValue* wForward = webview_value_new_bool(canGoForward);
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "isLoading", wLoading);
                    webview_value_set_string(retMap, "canGoBack", wBack);
                    webview_value_set_string(retMap, "canGoForward", wForward);
                    m_invokeFunc("onLoadingStateChanged", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(wLoading);
                    webview_value_unref(wBack);
                    webview_value_unref(wForward);
                    webview_value_unref(retMap);
                }
            };

            m_handler->onFindResult = [=](int nBrowserId, int count, int activeMatchOrdinal, bool finalUpdate)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(nBrowserId);
                    WValue* wCount = webview_value_new_int(count);
                    WValue* wOrdinal = webview_value_new_int(activeMatchOrdinal);
                    WValue* wFinal = webview_value_new_bool(finalUpdate);
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "count", wCount);
                    webview_value_set_string(retMap, "activeMatchOrdinal", wOrdinal);
                    webview_value_set_string(retMap, "finalUpdate", wFinal);
                    m_invokeFunc("onFindResult", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(wCount);
                    webview_value_unref(wOrdinal);
                    webview_value_unref(wFinal);
                    webview_value_unref(retMap);
                }
            };

            m_handler->onAdBlocked = [=](int nBrowserId, int count)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(nBrowserId);
                    WValue* wCount = webview_value_new_int(count);
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "count", wCount);
                    m_invokeFunc("onAdBlocked", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(wCount);
                    webview_value_unref(retMap);
                }
            };

            m_handler->onDownloadStart = [=](int browserId, std::string suggestedName, std::string url)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(browserId);
                    WValue* wName = webview_value_new_string(const_cast<char*>(suggestedName.c_str()));
                    WValue* wUrl = webview_value_new_string(const_cast<char*>(url.c_str()));
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "suggestedName", wName);
                    webview_value_set_string(retMap, "url", wUrl);
                    m_invokeFunc("onDownloadStart", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(wName);
                    webview_value_unref(wUrl);
                    webview_value_unref(retMap);
                }
            };

            m_handler->onDownloadUpdated = [=](int browserId, std::string url, int64_t receivedBytes, int64_t totalBytes, int percent, bool isComplete)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(browserId);
                    WValue* wUrl = webview_value_new_string(const_cast<char*>(url.c_str()));
                    WValue* wReceived = webview_value_new_int(receivedBytes);
                    WValue* wTotal = webview_value_new_int(totalBytes);
                    WValue* wPercent = webview_value_new_int(percent);
                    WValue* wComplete = webview_value_new_bool(isComplete);
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "url", wUrl);
                    webview_value_set_string(retMap, "receivedBytes", wReceived);
                    webview_value_set_string(retMap, "totalBytes", wTotal);
                    webview_value_set_string(retMap, "percent", wPercent);
                    webview_value_set_string(retMap, "isComplete", wComplete);
                    m_invokeFunc("onDownloadUpdated", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(wUrl);
                    webview_value_unref(wReceived);
                    webview_value_unref(wTotal);
                    webview_value_unref(wPercent);
                    webview_value_unref(wComplete);
                    webview_value_unref(retMap);
                }
            };

            m_handler->onContextMenu = [=](int browserId, int x, int y, int typeFlags, std::string linkUrl, std::string sourceUrl, std::string selectionText, bool isEditable)
            {
                if (m_invokeFunc)
                {
                    WValue* bId = webview_value_new_int(browserId);
                    WValue* wX = webview_value_new_int(x);
                    WValue* wY = webview_value_new_int(y);
                    WValue* wFlags = webview_value_new_int(typeFlags);
                    WValue* wLink = webview_value_new_string(const_cast<char*>(linkUrl.c_str()));
                    WValue* wSource = webview_value_new_string(const_cast<char*>(sourceUrl.c_str()));
                    WValue* wSelection = webview_value_new_string(const_cast<char*>(selectionText.c_str()));
                    WValue* wEditable = webview_value_new_bool(isEditable);
                    WValue* retMap = webview_value_new_map();
                    webview_value_set_string(retMap, "browserId", bId);
                    webview_value_set_string(retMap, "x", wX);
                    webview_value_set_string(retMap, "y", wY);
                    webview_value_set_string(retMap, "typeFlags", wFlags);
                    webview_value_set_string(retMap, "linkUrl", wLink);
                    webview_value_set_string(retMap, "sourceUrl", wSource);
                    webview_value_set_string(retMap, "selectionText", wSelection);
                    webview_value_set_string(retMap, "isEditable", wEditable);
                    m_invokeFunc("onContextMenu", retMap);
                    webview_value_unref(bId);
                    webview_value_unref(wX);
                    webview_value_unref(wY);
                    webview_value_unref(wFlags);
                    webview_value_unref(wLink);
                    webview_value_unref(wSource);
                    webview_value_unref(wSelection);
                    webview_value_unref(wEditable);
                    webview_value_unref(retMap);
                }
            };

			m_handler->onFileDialog = [=](int browserId, int callbackId)
			{
				if (m_invokeFunc)
				{
					WValue* bId = webview_value_new_int(browserId);
					WValue* cId = webview_value_new_int(callbackId);
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "callbackId", cId);
					m_invokeFunc("onFileDialog", retMap);
					webview_value_unref(bId);
					webview_value_unref(cId);
					webview_value_unref(retMap);
				}
			};

			m_handler->onExternalProtocol = [=](int browserId, std::string url)
			{
				if (m_invokeFunc)
				{
					WValue* bId = webview_value_new_int(browserId);
					WValue* wUrl = webview_value_new_string(const_cast<char*>(url.c_str()));
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "url", wUrl);
					m_invokeFunc("onExternalProtocol", retMap);
					webview_value_unref(bId);
					webview_value_unref(wUrl);
					webview_value_unref(retMap);
				}
			};

			m_handler->onBeforePopup = [=](int browserId, std::string targetUrl)
			{
				if (m_invokeFunc)
				{
					WValue* bId = webview_value_new_int(browserId);
					WValue* wUrl = webview_value_new_string(const_cast<char*>(targetUrl.c_str()));
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "targetUrl", wUrl);
					m_invokeFunc("onBeforePopup", retMap);
					webview_value_unref(bId);
					webview_value_unref(wUrl);
					webview_value_unref(retMap);
				}
			};

			m_handler->onPopupCreated = [=](int browserId)
			{
				std::lock_guard<std::recursive_mutex> lock(m_mutex);
				if (m_invokeFunc)
				{
					std::shared_ptr<WebviewTexture> renderer = m_createTextureFunc();
					m_renderers[browserId] = renderer;

					WValue* bId = webview_value_new_int(browserId);
					WValue* tId = webview_value_new_int(renderer->textureId);
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					webview_value_set_string(retMap, "textureId", tId);
					m_invokeFunc("onPopupCreated", retMap);
					webview_value_unref(bId);
					webview_value_unref(tId);
					webview_value_unref(retMap);
				}
			};

			m_handler->onBrowserClose = [=](int browserId)
			{
				if (m_invokeFunc)
				{
					WValue* bId = webview_value_new_int(browserId);
					WValue* retMap = webview_value_new_map();
					webview_value_set_string(retMap, "browserId", bId);
					m_invokeFunc("onBrowserClose", retMap);
					webview_value_unref(bId);
					webview_value_unref(retMap);
				}
			};

			m_init = true;
		}
	}

	void WebviewPlugin::uninitCallback(){
		m_handler->onPaintCallback = nullptr;
		m_handler->onTooltipEvent = nullptr;
		m_handler->onCursorChangedEvent = nullptr;
		m_handler->onConsoleMessageEvent = nullptr;
		m_handler->onUrlChangedEvent = nullptr;
		m_handler->onTitleChangedEvent = nullptr;
		m_handler->onJavaScriptChannelMessage = nullptr;
		m_handler->onFocusedNodeChangeMessage = nullptr;
		m_handler->onImeCompositionRangeChangedMessage = nullptr;
		m_handler->onLoadStart = nullptr;
		m_handler->onLoadEnd = nullptr;
		m_handler->onLoadError = nullptr;
		m_handler->onLoadingStateChanged = nullptr;
		m_handler->onFindResult = nullptr;
		m_handler->onAdBlocked = nullptr;
		m_handler->onDownloadStart = nullptr;
		m_handler->onDownloadUpdated = nullptr;
		m_handler->onContextMenu = nullptr;
		m_handler->onFileDialog = nullptr;
		m_handler->onExternalProtocol = nullptr;
		m_handler->onBeforePopup = nullptr;
		m_handler->onPopupCreated = nullptr;
		m_handler->onBrowserClose = nullptr;
		m_init = false;
	}


    void WebviewPlugin::HandleMethodCall(std::string name, WValue* values, std::function<void(int ,WValue*)> result) {
		std::lock_guard<std::recursive_mutex> lock(m_mutex);
		if (name.compare("init") == 0){
			if(!isCefInitialized){
				if(values != nullptr){
					userAgent = CefString(webview_value_get_string(values));
				}
				startCEF();
			}
			initCallback();
			result(1, nullptr);
		}
		else if (name.compare("quit") == 0) {
			//only call this method when you want to quit the app
			stopCEF();
			result(1, nullptr);
		}
		else if (name.compare("create") == 0) {
			std::string url = webview_value_get_string(values);
			m_handler->createBrowser(url, [=](int browserId) {
				std::shared_ptr<WebviewTexture> renderer = m_createTextureFunc();
				m_renderers[browserId] = renderer;
				WValue	*response = webview_value_new_list();
				webview_value_append(response, webview_value_new_int(browserId));
				webview_value_append(response, webview_value_new_int(renderer->textureId));
				result(1, response);
				webview_value_unref(response);
			});
		}
		else if (name.compare("close") == 0) {
			int browserId = int(webview_value_get_int(values));
			if (m_focusedBrowserId == browserId) {
				m_focusedBrowserId = -1;
				m_handler->setClientFocus(browserId, false);
			}
			m_handler->closeBrowser(browserId);
			m_renderers.erase(browserId);
			result(1, nullptr);
		}
		else if (name.compare("loadUrl") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			const auto url = webview_value_get_string(webview_value_get_list_value(values, 1));
			if(url != nullptr){
				m_handler->loadUrl(browserId, url);
				result(1, nullptr);
			}
		}
		else if (name.compare("setSize") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			const auto dpi = webview_value_get_double(webview_value_get_list_value(values, 1));
			const auto width = webview_value_get_double(webview_value_get_list_value(values, 2));
			const auto height = webview_value_get_double(webview_value_get_list_value(values, 3));
			m_handler->changeSize(browserId, (float)dpi, (int)std::round(width), (int)std::round(height));
			result(1, nullptr);
		}
		else if (name.compare("cursorClickDown") == 0 
			|| name.compare("cursorClickUp") == 0 
			|| name.compare("cursorMove") == 0 
			|| name.compare("cursorDragging") == 0) {
			result(cursorAction(values, name), nullptr);
		}
		else if (name.compare("setScrollDelta") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			auto x = webview_value_get_int(webview_value_get_list_value(values, 1));
			auto y = webview_value_get_int(webview_value_get_list_value(values, 2));
			auto deltaX = webview_value_get_int(webview_value_get_list_value(values, 3));
			auto deltaY = webview_value_get_int(webview_value_get_list_value(values, 4));
			m_handler->sendScrollEvent(browserId, (int)x, (int)y, (int)deltaX, -(int)deltaY);
			result(1, nullptr);
		}
		else if (name.compare("goForward") == 0) {
			int browserId = int(webview_value_get_int(values));
			m_handler->goForward(browserId);
			result(1, nullptr);
		}
		else if (name.compare("goBack") == 0) {
			int browserId = int(webview_value_get_int(values));
			m_handler->goBack(browserId);
			result(1, nullptr);
		}
		else if (name.compare("reload") == 0) {
			int browserId = int(webview_value_get_int(values));
			m_handler->reload(browserId);
			result(1, nullptr);
		}
		else if (name.compare("stopLoad") == 0) {
			int browserId = int(webview_value_get_int(values));
			m_handler->stopLoad(browserId);
			result(1, nullptr);
		}
		else if (name.compare("findInPage") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			const auto rawText = webview_value_get_string(webview_value_get_list_value(values, 1));
			bool forward = webview_value_get_bool(webview_value_get_list_value(values, 2));
			bool matchCase = webview_value_get_bool(webview_value_get_list_value(values, 3));
			bool findNext = webview_value_get_bool(webview_value_get_list_value(values, 4));
			m_handler->findInPage(browserId, rawText ? rawText : "", forward, matchCase, findNext);
			result(1, nullptr);
		}
		else if (name.compare("stopFinding") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			bool clearSelection = webview_value_get_bool(webview_value_get_list_value(values, 1));
			m_handler->stopFinding(browserId, clearSelection);
			result(1, nullptr);
		}
		else if (name.compare("setZoomLevel") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			double zoomLevel = webview_value_get_double(webview_value_get_list_value(values, 1));
			m_handler->setZoomLevel(browserId, zoomLevel);
			result(1, nullptr);
		}
		else if (name.compare("setAdBlockConfig") == 0) {
			bool enabled = webview_value_get_bool(webview_value_get_list_value(values, 0));
			WValue *domainList = webview_value_get_list_value(values, 1);
			WValue *whitelistList = webview_value_get_list_value(values, 2);
			std::vector<std::string> domains;
			if (domainList) {
				auto len = webview_value_get_len(domainList);
				domains.reserve(len);
				for (size_t i = 0; i < len; i++) {
					const auto s = webview_value_get_string(webview_value_get_list_value(domainList, i));
					if (s) domains.emplace_back(s);
				}
			}
			std::vector<std::string> whitelist;
			if (whitelistList) {
				auto len = webview_value_get_len(whitelistList);
				whitelist.reserve(len);
				for (size_t i = 0; i < len; i++) {
					const auto s = webview_value_get_string(webview_value_get_list_value(whitelistList, i));
					if (s) whitelist.emplace_back(s);
				}
			}
			m_handler->setAdBlockConfig(enabled, domains, whitelist);
			result(1, nullptr);
		}
		else if (name.compare("openDevTools") == 0) {			
			int browserId = int(webview_value_get_int(values));
			m_handler->openDevTools(browserId);
			result(1, nullptr);
		}
		else if (name.compare("imeSetComposition") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			const auto text = webview_value_get_string(webview_value_get_list_value(values, 1));
			m_handler->imeSetComposition(browserId, text);
			result(1, nullptr);
		} 
		else if (name.compare("imeCommitText") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			const auto text = webview_value_get_string(webview_value_get_list_value(values, 1));
			m_handler->imeCommitText(browserId, text);
			result(1, nullptr);
		} 
		else if (name.compare("setClientFocus") == 0) {
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			bool focus = webview_value_get_bool(webview_value_get_list_value(values, 1));
			if (focus) {
				for (auto& kv : m_renderers) {
					if (kv.second) {
						kv.second->isFocused = (kv.first == browserId);
					}
				}
				if (m_renderers.find(browserId) != m_renderers.end() && m_renderers[browserId] != nullptr) {
					m_focusedBrowserId = browserId;
					m_handler->setClientFocus(browserId, true);
				}
			} else {
				if (m_renderers.find(browserId) != m_renderers.end() && m_renderers[browserId] != nullptr) {
					m_renderers[browserId]->isFocused = false;
				}
				if (m_focusedBrowserId == browserId) {
					m_focusedBrowserId = -1;
					m_handler->setClientFocus(browserId, false);
				}
			}
			result(1, nullptr);
		}
		else if(name.compare("setCookie") == 0){
			const auto domain = webview_value_get_string(webview_value_get_list_value(values, 0));
			const auto key = webview_value_get_string(webview_value_get_list_value(values, 1));
			const auto value = webview_value_get_string(webview_value_get_list_value(values, 2));
			m_handler->setCookie(domain, key, value);
			result(1, nullptr);
		}
		else if (name.compare("deleteCookie") == 0) {
			const auto domain = webview_value_get_string(webview_value_get_list_value(values, 0));
			const auto key = webview_value_get_string(webview_value_get_list_value(values, 1));
			m_handler->deleteCookie(domain, key);
			result(1, nullptr);
		}
		else if (name.compare("visitAllCookies") == 0) {
			m_handler->visitAllCookies([=](std::map<std::string, std::map<std::string, std::string>> cookies){
				WValue* retMap = webview_value_new_map();
				for (auto &cookie : cookies)
				{
					WValue* tempMap = webview_value_new_map();
					for (auto &c : cookie.second)
					{
						WValue * val = webview_value_new_string(const_cast<char *>(c.second.c_str()));
						webview_value_set_string(tempMap, c.first.c_str(), val);
						webview_value_unref(val);
					}
					webview_value_set_string(retMap, cookie.first.c_str(), tempMap);
					webview_value_unref(tempMap);
				}
				result(1, retMap);	
				webview_value_unref(retMap);
			});
		}
		else if (name.compare("visitUrlCookies") == 0) {
			const auto domain = webview_value_get_string(webview_value_get_list_value(values, 0));
			const auto isHttpOnly = webview_value_get_bool(webview_value_get_list_value(values, 1));
			m_handler->visitUrlCookies(domain, isHttpOnly,[=](std::map<std::string, std::map<std::string, std::string>> cookies){
				WValue* retMap = webview_value_new_map();
				for (auto &cookie : cookies)
				{
					WValue* tempMap = webview_value_new_map();
					for (auto &c : cookie.second)
					{
						WValue * val = webview_value_new_string(const_cast<char *>(c.second.c_str()));
						webview_value_set_string(tempMap, c.first.c_str(), val);
						webview_value_unref(val);
					}
					webview_value_set_string(retMap, cookie.first.c_str(), tempMap);
					webview_value_unref(tempMap);
				}
				result(1, retMap);	
				webview_value_unref(retMap);
			});
		}
		else if(name.compare("setJavaScriptChannels") == 0){
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			WValue *list = webview_value_get_list_value(values, 1);
			auto len = webview_value_get_len(list);
			std::vector<std::string> channels;
			for(size_t i = 0; i < len; i++){
				auto channel = webview_value_get_string(webview_value_get_list_value(list, i));
				channels.push_back(channel);
			}
			m_handler->setJavaScriptChannels(browserId, channels);
			result(1, nullptr);
		}
		else if (name.compare("sendJavaScriptChannelCallBack") == 0) {
			const auto error = webview_value_get_bool(webview_value_get_list_value(values, 0));
			const auto ret = webview_value_get_string(webview_value_get_list_value(values, 1));
			const auto callbackId = webview_value_get_string(webview_value_get_list_value(values, 2));
			const auto browserId = int(webview_value_get_int(webview_value_get_list_value(values, 3)));
			const auto frameId = webview_value_get_string(webview_value_get_list_value(values, 4));
			m_handler->sendJavaScriptChannelCallBack(error, ret, callbackId, browserId, frameId);
			result(1, nullptr);
		}
		else if(name.compare("executeJavaScript") == 0){
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			const auto code = webview_value_get_string(webview_value_get_list_value(values, 1));
			m_handler->executeJavaScript(browserId, code);
			result(1, nullptr);
		}
		else if (name.compare("continueFileDialog") == 0) {
			int callbackId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			WValue *list = webview_value_get_list_value(values, 1);
			auto len = webview_value_get_len(list);
			std::vector<std::string> filePaths;
			for(size_t i = 0; i < len; i++){
				auto path = webview_value_get_string(webview_value_get_list_value(list, i));
				filePaths.push_back(path);
			}
			m_handler->continueFileDialog(callbackId, filePaths);
			result(1, nullptr);
		}
		else if(name.compare("evaluateJavascript") == 0){
			int browserId = int(webview_value_get_int(webview_value_get_list_value(values, 0)));
			const auto code = webview_value_get_string(webview_value_get_list_value(values, 1));
			m_handler->executeJavaScript(browserId, code, [=](CefRefPtr<CefValue> values){
                WValue* retValue;

                if (values == nullptr) {
                    result(1, nullptr);
                    return;
                }

                switch(values->GetType()) {
                    case VTYPE_BOOL:
                        retValue = webview_value_new_bool(values->GetBool());
                        break;
                    case VTYPE_DOUBLE:
                        retValue = webview_value_new_double(values->GetDouble());
                        break;
                    case VTYPE_INT:
                        retValue = webview_value_new_int(values->GetInt());
                        break;
                    case VTYPE_STRING:
                        retValue = webview_value_new_string(values->GetString().ToString().c_str());
                        break;
                    case VTYPE_LIST: {
                        retValue = webview_value_new_list();
                        CefRefPtr<CefListValue> list = values->GetList();
                        
                        if (list) {
                            for (size_t i = 0; i < list->GetSize(); ++i) {
                                CefValueType type = list->GetType(i);
                                CefRefPtr<CefValue> listItem = list->GetValue(i);

                                if (type == VTYPE_INT) {
                                    webview_value_append(retValue, webview_value_new_int(listItem->GetInt()));
                                } else if (type == VTYPE_BOOL) {
                                    webview_value_append(retValue, webview_value_new_bool(listItem->GetBool()));
                                } else if (type == VTYPE_STRING) {
                                    webview_value_append(retValue, webview_value_new_string(listItem->GetString().ToString().c_str()));
                                } else if (type == VTYPE_DOUBLE) {
                                    webview_value_append(retValue, webview_value_new_double(listItem->GetDouble()));
                                } else {
                                    continue;
                                }
                            }
                        }
                        break;
                    }
                    default:
                        // Return null as fallback
                        result(1, nullptr);
                        return;
                }

				result(1, retValue);
				webview_value_unref(retValue);
			});
		}
		else {
			result(0, nullptr);
		}
	}

	void WebviewPlugin::sendKeyEvent(CefKeyEvent& ev)
	{
		std::lock_guard<std::recursive_mutex> lock(m_mutex);
		if (m_focusedBrowserId == -1 || m_renderers.find(m_focusedBrowserId) == m_renderers.end()) {
			return;
		}
		m_handler->sendKeyEvent(m_focusedBrowserId, ev);

		if(ev.type == KEYEVENT_RAWKEYDOWN && ev.windows_key_code == 0x7B && (ev.modifiers & EVENTFLAG_CONTROL_DOWN) != 0){
			m_handler->openDevTools(m_focusedBrowserId);
		}
	}

	void WebviewPlugin::setInvokeMethodFunc(std::function<void(std::string, WValue*)> func){
		m_invokeFunc = func;
	}

	void WebviewPlugin::setLogNativeFunc(std::function<void(std::string)> func){
		m_logFunc = func;
	}

	void WebviewPlugin::setCreateTextureFunc(std::function<std::shared_ptr<WebviewTexture>()> func)
	{
		m_createTextureFunc = func;
	}
	
	bool WebviewPlugin::getAnyBrowserFocused(){
		std::lock_guard<std::recursive_mutex> lock(m_mutex);
		return m_focusedBrowserId != -1 && m_renderers.find(m_focusedBrowserId) != m_renderers.end();
	}
	
	int WebviewPlugin::cursorAction(WValue *args, std::string name) {
		auto len = webview_value_get_len(args);
		if (!args || len < 3) {
			return 0;
		}
		int browserId = int(webview_value_get_int(webview_value_get_list_value(args, 0)));
		int x = int(webview_value_get_int(webview_value_get_list_value(args, 1)));
		int y = int(webview_value_get_int(webview_value_get_list_value(args, 2)));
		int button = 0;
		if (len >= 4) {
			button = int(webview_value_get_int(webview_value_get_list_value(args, 3)));
		}

		if (name.compare("cursorClickDown") == 0) {
			m_handler->cursorClick(browserId, x, y, false, button);
		}
		else if (name.compare("cursorClickUp") == 0) {
			m_handler->cursorClick(browserId, x, y, true, button);
		}
		else if (name.compare("cursorMove") == 0) {
			m_handler->cursorMove(browserId, x, y, false);
		}
		else if (name.compare("cursorDragging") == 0) {
			m_handler->cursorMove(browserId, x, y, true);
		}
		return 1;
	}

	int initCEFProcesses(CefMainArgs args){
		mainArgs = args;
		return initCEFProcesses();
	}

	int initCEFProcesses(){
#ifdef OS_MAC
		CefScopedLibraryLoader loader;
		if(!loader.LoadInMain()) {
			printf("load cef err");
		}
#endif
		// handler = new WebviewHandler();
		app = new WebviewApp();
		return CefExecuteProcess(mainArgs, app, nullptr);
	}

	void startCEF()
	{
		CefSettings cefs;
		cefs.windowless_rendering_enabled = true;
		cefs.no_sandbox = true;

        // FyrBrowser: Set persistent cache path
        const char* homedir = getenv("HOME");
        if (homedir != nullptr) {
            std::string cache_path = std::string(homedir) + "/.config/fyrbrowser";
            CefString(&cefs.root_cache_path) = cache_path;
            CefString(&cefs.cache_path) = cache_path + "/cef_cache";
        }
        
        cefs.persist_session_cookies = true;

        // FyrBrowser: Enable internal CEF logging
        if (homedir != nullptr) {
            std::string log_path = std::string(homedir) + "/.config/fyrbrowser/logs/cef.log";
            CefString(&cefs.log_file) = log_path;
            cefs.log_severity = LOGSEVERITY_DEFAULT; // Adjust if needed (LOGSEVERITY_VERBOSE, etc.)
        }

		if(!userAgent.empty()){
			CefString(&cefs.user_agent) = userAgent;
		}
		//locale language setting
		//CefString(&cefs.locale) = "zh-CN";
#ifdef OS_MAC
		//cef message loop handle by MainApplication on mac
		cefs.external_message_pump = true;
		//CefString(&cefs.browser_subprocess_path) = "/Library/Chaches"; //the helper Program path
#else
		//cef message run in another thread on windows/linux
		cefs.multi_threaded_message_loop = true;
#endif
		CefInitialize(mainArgs, cefs, app.get(), nullptr);
	}

	void doMessageLoopWork(){
		CefDoMessageLoopWork();
	}

	void SwapBufferFromBgraToRgba(void* _dest, const void* _src, int width, int height) {
		uint32_t* __restrict dest = static_cast<uint32_t*>(_dest);
		const uint32_t* __restrict src = static_cast<const uint32_t*>(_src);
		const int length = width * height;
		for (int i = 0; i < length; i++) {
			const uint32_t bgra = src[i];
			dest[i] = ((bgra & 0x00ff0000u) >> 16)
				| (bgra & 0xff00ff00u)
				| ((bgra & 0x000000ffu) << 16);
		}
	}

    void stopCEF()
    {
		CefShutdown();
    }
}
