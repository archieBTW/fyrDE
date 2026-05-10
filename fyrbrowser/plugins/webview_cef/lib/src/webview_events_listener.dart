import 'package:webview_cef/src/webview.dart';

typedef TitleChangeCb = void Function(String title);
typedef UrlChangeCb = void Function(String url);
/* Log severity levels. from CEF include/internal/cef_types.h
  0:default logging (currently info logging)
  1:verbose logging or debug logging
  2:info logging
  3:warning logging
  4:error logging
  5:fatal logging
  99:disable logging to file for all messages, and to stderr for messages with severity less than fatal
 */
typedef LoadStartCb = void Function(WebViewController controller, String url);
typedef LoadStopCb = void Function(WebViewController controller, String url);

typedef DownloadStartCb = void Function(
    String suggestedName, String url);
typedef DownloadUpdatedCb = void Function(
    String url, int receivedBytes, int totalBytes, int percent, bool isComplete);

typedef ContextMenuCb = void Function(
    int x, int y, int typeFlags, String linkUrl, String sourceUrl, String selectionText, bool isEditable);
typedef OnFileDialogCb = void Function(int browserId, int callbackId);

typedef OnConsoleMessage = void Function(
    int level, String message, String source, int line);
typedef ExternalProtocolCb = void Function(String url);
typedef BeforePopupCb = void Function(String targetUrl);

class WebviewEventsListener {
  TitleChangeCb? onTitleChanged;
  UrlChangeCb? onUrlChanged;
  OnConsoleMessage? onConsoleMessage;
  LoadStartCb? onLoadStart;
  LoadStopCb? onLoadEnd;
  DownloadStartCb? onDownloadStart;
  DownloadUpdatedCb? onDownloadUpdated;
  ContextMenuCb? onContextMenu;
  OnFileDialogCb? onFileDialog;
  ExternalProtocolCb? onExternalProtocol;
  BeforePopupCb? onBeforePopup;
  final void Function()? onClose;

  WebviewEventsListener({
    this.onTitleChanged,
    this.onUrlChanged,
    this.onConsoleMessage,
    this.onLoadStart,
    this.onLoadEnd,
    this.onDownloadStart,
    this.onDownloadUpdated,
    this.onContextMenu,
    this.onFileDialog,
    this.onExternalProtocol,
    this.onBeforePopup,
    this.onClose,
  });
}
