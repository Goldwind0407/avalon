/// Whether this page runs isolated from other sites (see web_page_web.dart).
bool get pageIsolated => false;

/// Opens the separate sign-in page (web only).
void openSignInPage() {}

/// A flag kept on this device (web: localStorage); false when unset.
bool readFlag(String key) => false;
void writeFlag(String key, bool value) {}

/// Tells the web page what is on screen (web only).
void showStage(String stage) {}
