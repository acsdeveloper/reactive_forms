// This file provides stub implementations for web-specific functionality
// It's used as a fallback when not running on the web platform

// Stub class to mimic html.Window
class Window {
  void open(String url, String name, [String? options]) {
    // This is a stub, it doesn't do anything on non-web platforms
    print('Cannot open URL in a new window on non-web platforms');
  }
}

// Stub class for ElementStyle
class ElementStyle {
  String _display = '';
  String get display => _display;
  set display(String value) => _display = value;

  @override
  String toString() => _display;
}

// Stub class for Element
class Element {
  // Make style an ElementStyle object
  ElementStyle style = ElementStyle();

  // Add parent property
  Element? parent;

  // Add children list for Element manipulation
  List<Element> children = [];

  void setAttribute(String name, String value) {}
  void click() {}

  // Method to remove element from DOM
  void remove() {
    // In a real implementation, this would remove the element from its parent
    if (parent != null) {
      parent!.children.remove(this);
      parent = null;
    }
  }
}

// Stub class for AnchorElement that extends Element
class AnchorElement extends Element {
  AnchorElement({String? href}) {
    if (href != null) this._href = href;
  }

  String _href = '';
  String get href => _href;
  set href(String value) => _href = value;

  String _download = '';
  String get download => _download;
  set download(String value) => _download = value;
}

// Stub class for Document
class Document {
  Body? body;

  Element? createElement(String tagName) {
    return null;
  }
}

// Stub class for Body that extends Element
class Body extends Element {
  List<Element> _childElements = [];

  @override
  List<Element> get children => _childElements;

  void append(Element element) {
    _childElements.add(element);
    element.parent = this; // No cast needed since Body is now an Element
  }

  void removeChild(Element element) {
    _childElements.remove(element);
    element.parent = null;
  }
}

// Stub class for Url
class Url {
  static String createObjectUrlFromBlob(Blob blob) {
    return '';
  }

  static void revokeObjectUrl(String url) {}
}

// Stub class for Blob
class Blob {
  // Updated constructor to handle both the content and the MIME type
  Blob(List<dynamic> parts, [String? type]) {
    // Store the MIME type if provided
    if (type != null) {
      _mimeType = type;
    }
  }

  String _mimeType = 'application/octet-stream';
  String get type => _mimeType;
}

// Stub html object with properties and methods
final window = Window();
final document = Document()..body = Body();

// Stub extension methods
extension UriDataExtension on Uri {
  String get data => '';
}

// Stub function to create a blob URL
String createObjectUrlFromBlob(dynamic blob) {
  return '';
}

// Stub function for blob creation
dynamic createBlob(List<dynamic> data, String type) {
  return null;
}
