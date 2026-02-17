import 'package:flutter/widgets.dart';

enum GameContextAction {
  viewDetails,
  compress,
  decompress,
  exclude,
  openFolder,
}

class CompressIntent extends Intent {
  const CompressIntent();
}

class ExcludeIntent extends Intent {
  const ExcludeIntent();
}

class OpenFolderIntent extends Intent {
  const OpenFolderIntent();
}

class OpenDetailsIntent extends Intent {
  const OpenDetailsIntent();
}

class ContextMenuIntent extends Intent {
  const ContextMenuIntent();
}
