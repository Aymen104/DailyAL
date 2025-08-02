import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/generated/l10n.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/pages/settings/customsettings.dart';
import 'package:dailyanimelist/pages/settings/optiontile.dart';
import 'package:dailyanimelist/theme/font_family.dart';
import 'package:dailyanimelist/widgets/selectbottom.dart';
import 'package:flutter/material.dart';

class FontSettings extends StatefulWidget {
  final bool isIntroPage;
  const FontSettings({super.key, this.isIntroPage = false});

  @override
  State<FontSettings> createState() => _FontSettingsState();
}

class _FontSettingsState extends State<FontSettings> {
  UserFont currentFont = UserFont.values.firstWhere(
    (font) => fontFamilyMap[font] == user.pref.preferredFont,
    orElse: () => UserFont.Poppins,
  );


  @override
  Widget build(BuildContext context) {
    return SettingSliverScreen(
      titleString: S.current.Font_Settings,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _save();
          if (widget.isIntroPage) {
            Navigator.pop(context);
            return;
          }
          restartApp(context);
        },
        label: Text(S.current.Save),
        icon: const Icon(Icons.save),
      ),
      child: SliverList.list(
        children: [
          SB.h30,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 25),
            child: text(S.current.Font_Instructions,
                fontSize: 16),
          ),
          SB.h20,
          _fontFamilySelector(),
          SB.h30,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 25),
            child: text(S.current.Font_Preview, fontSize: 20),
          ),
          SB.h20,
          _fontPreview(),
          SB.h120,
        ],
      ),
    );
  }

  Widget _fontFamilySelector() {
    return OptionTile(
      text: S.current.Font_Family,
      iconData: Icons.font_download_outlined,
      multiLine: false,
      desc: S.current.Font_Family_desc,
      onPressed: () {},
      trailing: SelectButton(
        popupText: S.current.Select_Font_Family,
        selectedOption: fontFamilyDisplayMap[UserFont.values.firstWhere(
              (font) => font == currentFont,
              orElse: () => UserFont.Poppins,
            )] ??
            'Poppins',
        options: fontFamilyDisplayMap.values.toList(),
        onChanged: (value) {
          final font = fontFamilyDisplayMap.entries
              .firstWhere(
                (entry) => entry.value == value,
              )
              .key;

          currentFont = font;

          setState(() {});
        },
      ),
    );
  }

  _save() {
    user.pref.preferredFont = fontFamilyMap[currentFont]!;
    user.setIntance();
  }

  Widget _fontPreview() {
    var current = fontFamilyMap[currentFont];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.current.Font_Sample_Text,
                style: TextStyle(
                  fontFamily: current,
                  fontSize: 16,
                ),
              ),
              SB.h10,
              Text(
                'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                style: TextStyle(
                  fontFamily: current,
                  fontSize: 16,
                ),
              ),
              SB.h10,
              Text(
                'abcdefghijklmnopqrstuvwxyz',
                style: TextStyle(
                  fontFamily: current,
                  fontSize: 16,
                ),
              ),
              SB.h10,
              Text(
                '0123456789',
                style: TextStyle(
                  fontFamily: current,
                  fontSize: 16,
                ),
              ),
              SB.h20,
              Text(
                S.current.Font_Heading_Sample,
                style: TextStyle(
                  fontFamily: current,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SB.h10,
              Text(
                S.current.Font_Preview_Description,
                style: TextStyle(
                  fontFamily: current,
                  fontSize: 14,
                ),
              ),
              SB.h10,
              Text(
                S.current.Font_Restart_Notice,
                style: TextStyle(
                  fontFamily: current,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
