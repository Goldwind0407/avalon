/// The table drawn by the web page itself (web/table/): only in a browser.
bool get tablePageAvailable => false;

void openTablePage(String Function(String type, String arg) host) {}
void updateTablePage(String state) {}
void tablePageEvent(String event) {}
void coverTablePage(bool covered) {}
void closeTablePage() {}
