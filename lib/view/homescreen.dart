import 'dart:async';
import 'package:badgemagic/bademagic_module/utils/byte_array_utils.dart';
import 'package:badgemagic/bademagic_module/utils/converters.dart';
import 'package:badgemagic/bademagic_module/utils/image_utils.dart';
import 'package:badgemagic/bademagic_module/utils/toast_utils.dart';
import 'package:badgemagic/badge_effect/flash_effect.dart';
import 'package:badgemagic/badge_effect/invert_led_effect.dart';
import 'package:badgemagic/badge_effect/marquee_effect.dart';
import 'package:badgemagic/constants.dart';
import 'package:badgemagic/providers/animation_badge_provider.dart';
import 'package:badgemagic/providers/badge_message_provider.dart';
import 'package:badgemagic/providers/font_provider.dart';
import 'package:badgemagic/providers/imageprovider.dart';
import 'package:badgemagic/providers/speed_dial_provider.dart';
import 'package:badgemagic/view/special_text_field.dart';
import 'package:badgemagic/view/widgets/common_scaffold_widget.dart';
import 'package:badgemagic/view/widgets/homescreentabs.dart';
import 'package:badgemagic/view/widgets/save_badge_dialog.dart';
import 'package:badgemagic/view/widgets/speedial.dart';
import 'package:badgemagic/view/widgets/vectorview.dart';
import 'package:badgemagic/virtualbadge/view/animated_badge.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver {
  late final TabController _tabController;
  late SpeedDialProvider speedDialProvider;
  final AnimationBadgeProvider animationProvider = AnimationBadgeProvider();
  final BadgeMessageProvider badgeData = BadgeMessageProvider();
  final ImageUtils imageUtils = ImageUtils();
  final InlineImageProvider inlineImageProvider =
      GetIt.instance<InlineImageProvider>();
  final TextEditingController inlineimagecontroller =
      GetIt.instance.get<InlineImageProvider>().getController();

  bool isPrefixIconClicked = false;
  bool isDialInteracting = false;
  String previousText = '';
  String _cachedText = ''; // <-- NEW: to cache text on pause

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    inlineimagecontroller.addListener(handleTextChange);
    _setPortraitOrientation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      inlineImageProvider.setContext(context);
    });
    _startImageCaching();
    speedDialProvider = SpeedDialProvider(animationProvider);
    _tabController = TabController(length: 3, vsync: this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    inlineimagecontroller.removeListener(handleTextChange);
    inlineimagecontroller.removeListener(_controllerListner);
    animationProvider.stopAnimation();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _cachedText = inlineimagecontroller.text;
      animationProvider.stopAnimation();
    } else if (state == AppLifecycleState.resumed) {
      if (inlineimagecontroller.text.trim().isEmpty &&
          _cachedText.trim().isNotEmpty) {
        inlineimagecontroller.text = _cachedText;
      }
      animationProvider.badgeAnimation(
        inlineimagecontroller.text,
        Converters(),
        animationProvider.isEffectActive(InvertLEDEffect()),
      );
    }
  }

  void _controllerListner() {
    animationProvider.badgeAnimation(
      inlineImageProvider.getController().text,
      Converters(),
      animationProvider.isEffectActive(InvertLEDEffect()),
    );
  }

  void handleTextChange() {
    final currentText = inlineimagecontroller.text;
    final selection = inlineimagecontroller.selection;

    if (previousText.length > currentText.length) {
      final deletionIndex = selection.baseOffset;
      final regex = RegExp(r'<<\d+>>');
      final matches = regex.allMatches(previousText);

      bool placeholderDeleted = false;

      for (final match in matches) {
        if (deletionIndex > match.start && deletionIndex < match.end) {
          inlineimagecontroller.text =
              previousText.replaceRange(match.start, match.end, '');
          inlineimagecontroller.selection =
              TextSelection.collapsed(offset: match.start);
          placeholderDeleted = true;
          break;
        }
      }

      if (!placeholderDeleted) {
        previousText = inlineimagecontroller.text;
      }
    } else {
      previousText = currentText;
    }
  }

  void _setPortraitOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  Future<void> _startImageCaching() async {
    if (!inlineImageProvider.isCacheInitialized) {
      await inlineImageProvider.generateImageCache();
      setState(() {
        inlineImageProvider.isCacheInitialized = true;
      });
    }
  }

  TextStyle _getFontStyle(String fontName) {
    const baseStyle = TextStyle(fontSize: 12);
    switch (fontName) {
      case 'Roboto':
        return GoogleFonts.roboto(
            textStyle: baseStyle.copyWith(fontWeight: FontWeight.w700));
      case 'Open Sans':
        return GoogleFonts.openSans(
            textStyle: baseStyle.copyWith(fontWeight: FontWeight.w700));
      case 'Lato':
        return GoogleFonts.lato(
            textStyle: baseStyle.copyWith(fontWeight: FontWeight.w700));
      case 'Poppins':
        return GoogleFonts.poppins(
            textStyle: baseStyle.copyWith(fontWeight: FontWeight.w700));
      case 'Montserrat':
        return GoogleFonts.montserrat(
            textStyle: baseStyle.copyWith(fontWeight: FontWeight.w700));
      case 'Orbitron':
        return GoogleFonts.orbitron(
            textStyle: baseStyle.copyWith(fontWeight: FontWeight.w700));
      case 'Lexend':
        return GoogleFonts.lexend(
            textStyle: baseStyle.copyWith(fontWeight: FontWeight.w700));
      default:
        return baseStyle;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AnimationBadgeProvider>(
          create: (_) => animationProvider,
        ),
        ChangeNotifierProvider<SpeedDialProvider>(
          create: (_) {
            inlineimagecontroller.addListener(_controllerListner);
            return speedDialProvider;
          },
        ),
      ],
      child: DefaultTabController(
          length: 3,
          child: CommonScaffold(
            index: 0,
            title: 'Badge Magic',
            body: SafeArea(
              child: SingleChildScrollView(
                physics: isDialInteracting
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    AnimationBadge(),
                    Container(
                      margin: EdgeInsets.all(15.w),
                      child: Material(
                        color: drawerHeaderTitle,
                        borderRadius: BorderRadius.circular(10.r),
                        elevation: 4,
                        child: ExtendedTextField(
                    controller: inlineimagecontroller,
                    specialTextSpanBuilder: ImageBuilder(),
                    style: Provider.of<FontProvider>(context).selectedFont != null
                        ? _getFontStyle(Provider.of<FontProvider>(context)
                                .selectedFont!)
                            .copyWith(fontSize: 14)
                        : const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        borderSide: BorderSide(color: colorPrimary),
                      ),
                      prefixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            isPrefixIconClicked = !isPrefixIconClicked;
                          });
                        },
                        icon: const Icon(Icons.tag_faces_outlined),
                      ),
                      suffixIcon: Padding(
                        padding: EdgeInsets.only(right: 8.w),
                        child: Consumer<FontProvider>(
                          builder: (context, fontProvider, _) {
                            return DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: fontProvider.selectedFont,
                                icon: const Icon(Icons.arrow_drop_down),
                                hint: Text(
                                  'Font',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text(
                                      'Default Font',
                                      style: TextStyle(
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  ...fontProvider.availableFonts.map((font) => DropdownMenuItem(
                                        value: font,
                                        child: Text(
                                          font,
                                          style: _getFontStyle(font),
                                        ),
                                      ))
                                ],
                                onChanged: (String? newFont) {
                                  fontProvider.changeFont(newFont);
                                  animationProvider.badgeAnimation(
                                    inlineimagecontroller.text,
                                    Converters(),
                                    animationProvider.isEffectActive(
                                        InvertLEDEffect()),
                                  );
                                },
                                borderRadius: BorderRadius.circular(8.r),
                                elevation: 2,
                                isDense: true,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
                  Visibility(
                    visible: isPrefixIconClicked,
                    child: Container(
                      height: 170.h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.r),
                        color: Colors.grey[200],
                      ),
                      margin: EdgeInsets.symmetric(horizontal: 15.w),
                      padding: EdgeInsets.symmetric(
                          vertical: 10.h, horizontal: 10.w),
                      child: VectorGridView(),
                    ),
                  ),
                  TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.black,
                    unselectedLabelColor: mdGrey400,
                    indicatorColor: colorPrimary,
                    controller: _tabController,
                    splashFactory: InkRipple.splashFactory,
                    overlayColor: WidgetStateProperty.resolveWith<Color?>(
                      (states) => states.contains(WidgetState.pressed)
                          ? dividerColor
                          : null,
                    ),
                    tabs: const [
                      Tab(text: 'Speed'),
                      Tab(text: 'Animation'),
                      Tab(text: 'Effects'),
                    ],
                  ),
                  SizedBox(
                    height: 250.h,
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      controller: _tabController,
                      children: [
                        GestureDetector(
                          onPanDown: (_) =>
                              setState(() => isDialInteracting = true),
                          onPanCancel: () =>
                              setState(() => isDialInteracting = false),
                          onPanEnd: (_) =>
                              setState(() => isDialInteracting = false),
                          child: RadialDial(),
                        ),
                        AnimationTab(),
                        EffectTab(),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 20.h),
                        child: GestureDetector(
                          onTap: () {
                            if (inlineimagecontroller.text.trim().isEmpty) {
                              ToastUtils()
                                  .showErrorToast("Please enter a message");
                              return;
                            }
                            showDialog(
                              context: context,
                              builder: (context) {
                                return SaveBadgeDialog(
                                  speed: speedDialProvider,
                                  animationProvider: animationProvider,
                                  textController: inlineimagecontroller,
                                  isInverse: animationProvider
                                      .isEffectActive(InvertLEDEffect()),
                                );
                              },
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 33.w, vertical: 8.h),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2.r),
                              color: mdGrey400,
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                      ),
                      SizedBox(width: 100.w),
                      Container(
                        padding: EdgeInsets.symmetric(vertical: 20.h),
                        child: GestureDetector(
                          onTap: () {
                            badgeData.checkAndTransfer(
                              inlineimagecontroller.text,
                              animationProvider.isEffectActive(FlashEffect()),
                              animationProvider.isEffectActive(MarqueeEffect()),
                              animationProvider
                                  .isEffectActive(InvertLEDEffect()),
                              speedDialProvider.getOuterValue(),
                              modeValueMap[
                                  animationProvider.getAnimationIndex()],
                              null,
                              false,
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 20.w, vertical: 8.h),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2.r),
                              color: mdGrey400,
                            ),
                            child: const Text('Transfer'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
