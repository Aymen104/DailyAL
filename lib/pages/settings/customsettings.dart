import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/pages/settings/settingheader.dart';
import 'package:flutter/material.dart';

class SettingSliverScreen extends StatelessWidget {
  final Widget? child;
  final List<Widget>? children;
  final bool showBackButton;
  final Widget? floatingActionButton;
  final String titleString;
  const SettingSliverScreen({
    Key? key,
    this.children,
    this.child,
    this.showBackButton = true,
    required this.titleString, this.floatingActionButton,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: CustomScrollView(
        slivers: [
          SettingsSliverHeader(title: titleString),
          SB.lh30,
          if (child != null) child!,
          if (children != null) ...children!,
        ],
      ),
    );
  }
}
