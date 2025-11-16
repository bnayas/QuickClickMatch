import 'package:flutter/material.dart';

class UnsupportedPlatformScreen extends StatelessWidget {
  final String message;
  const UnsupportedPlatformScreen({this.message = 'Not supported on this platform', Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text(message)),
  );
}
class DebugEditScreen extends UnsupportedPlatformScreen {
  const DebugEditScreen({Key? key}) : super(key: key, message: 'DebugEditScreen is not supported on this platform.');
}
