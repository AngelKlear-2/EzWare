// Tweak.m - EzWare: ESP + skeleton + settings menu for StandChillow 2.07 F1 (iOS 15, IL2CPP)
// RVAs and offsets come from ios_dump of 2.07 F1. Not tested on device yet:
// the menu footer shows "players N" and "hook ok/no" so each step can be checked.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <math.h>
#import <string.h>
#import <substrate.h>

// ---------------------------------------------------------------- RVAs (script.json "Address")
#define RVA_PM_DICT   0x2822ea0   // PlayerManager.oeh()        -> Dictionary<int, PlayerController>
#define RVA_PM_AWAKE  0x2823384   // PlayerManager.Awake(this)  (hooked to capture the instance)
#define RVA_CAM_MAIN  0x63e162c   // Camera.get_main()
#define RVA_CAM_W2S   0x63e0f38   // Camera.WorldToScreenPoint(this, Vector3, MethodInfo*)
#define RVA_SCR_W     0x63edd30   // Screen.get_width()
#define RVA_SCR_H     0x63edd70   // Screen.get_height()
#define RVA_COMP_TR   0x641c634   // Component.get_transform(this)
#define RVA_TR_POS    0x642ce44   // Transform.get_position(this)

// ---------------------------------------------------------------- field offsets (iOS dump)
#define OFF_PM_LOCAL   0x40       // PlayerManager.<cfla>k__BackingField (local PlayerController)
#define OFF_PC_BIPED   0x30       // PlayerController._characterBiped (BipedMap)
#define OFF_PC_TEAM    0x79       // PlayerController.<cfif>k__BackingField (Team byte)
// System.Collections.Generic.Dictionary<int,V> layout (CoreCLR auto layout, refs first)
#define OFF_DICT_ENTRIES 0x18     // _entries
#define OFF_ARR_LEN      0x18     // Il2CppArray max_length
#define OFF_ARR_DATA     0x20     // Il2CppArray vector start
#define ENTRY_STRIDE     0x18     // Entry<int,PlayerController>: hash,next,key,value

enum { BN_HEAD, BN_NECK, BN_SPINE2, BN_SPINE1, BN_SPINE, BN_HIP,
       BN_LSH, BN_LUA, BN_LFA, BN_LHA, BN_RSH, BN_RUA, BN_RFA, BN_RHA,
       BN_LUL, BN_LLE, BN_LFO, BN_RUL, BN_RLE, BN_RFO, BN_COUNT };
// BipedMap public Transform fields (iOS dump)
static const uint32_t kBoneOff[BN_COUNT] = {
    0x20, 0x28, 0x40, 0x38, 0x30, 0x88,
    0x48, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80,
    0x90, 0x98, 0xA0, 0xB0, 0xB8, 0xC0 };
static const int kPairs[][2] = {
    {BN_HEAD,BN_NECK},{BN_NECK,BN_SPINE2},{BN_SPINE2,BN_SPINE1},{BN_SPINE1,BN_SPINE},{BN_SPINE,BN_HIP},
    {BN_SPINE2,BN_LSH},{BN_LSH,BN_LUA},{BN_LUA,BN_LFA},{BN_LFA,BN_LHA},
    {BN_SPINE2,BN_RSH},{BN_RSH,BN_RUA},{BN_RUA,BN_RFA},{BN_RFA,BN_RHA},
    {BN_HIP,BN_LUL},{BN_LUL,BN_LLE},{BN_LLE,BN_LFO},
    {BN_HIP,BN_RUL},{BN_RUL,BN_RLE},{BN_RLE,BN_RFO} };

// ---------------------------------------------------------------- settings (NSUserDefaults)
#define D [NSUserDefaults standardUserDefaults]
static BOOL gB(NSString *k) { return [D boolForKey:k]; }
static float gF(NSString *k) { return [D floatForKey:k]; }
static NSInteger gI(NSString *k) { return [D integerForKey:k]; }
static void sV(NSString *k, id v) { [D setObject:v forKey:k]; }

static const uint32_t kPalette[8] = { 0x8F7BFF, 0xFF4D4D, 0x3DDC84, 0x35D0FF, 0xFFD60A, 0xFFFFFF, 0xFF9F0A, 0xFF5FA2 };
static UIColor *PalColor(NSInteger i) {
    uint32_t h = kPalette[((i % 8) + 8) % 8];
    return [UIColor colorWithRed:((h >> 16) & 0xff) / 255.0 green:((h >> 8) & 0xff) / 255.0 blue:(h & 0xff) / 255.0 alpha:1];
}

// ---------------------------------------------------------------- IL2CPP calls by RVA
typedef struct { float x, y, z; } V3;
typedef void *(*Fn_Ptr0)(void *m);
typedef void *(*Fn_Ptr1)(void *self, void *m);
typedef V3 (*Fn_Vec1)(void *self, void *m);
typedef V3 (*Fn_W2S)(void *self, V3 p, void *m);
typedef int32_t (*Fn_Int0)(void *m);
typedef void (*Fn_Awake)(void *self, void *m);

static uintptr_t gBase = 0;
static void *gPM = NULL;          // PlayerManager instance, captured in Awake
static Fn_Awake o_Awake = NULL;
static BOOL gHookOK = NO;

static void h_Awake(void *self, void *m) {
    gPM = self;
    if (o_Awake) o_Awake(self, m);
}

static uintptr_t ResolveBase(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

static void InstallHooks(void) {
    gBase = ResolveBase();
    if (!gBase) return;
    MSHookFunction((void *)(gBase + RVA_PM_AWAKE), (void *)h_Awake, (void **)&o_Awake);
    gHookOK = YES;
}

// ---------------------------------------------------------------- world snapshot (main thread, 30 Hz)
typedef struct {
    CGPoint feet, head, bones[BN_COUNT];
    BOOL fOk, hOk, bOk[BN_COUNT];
    BOOL enemy;
    uint8_t team;
    float dist;
} Ent;

#define MAX_ENTS 64
static Ent gEnts[MAX_ENTS];
static int gEntN = 0;
static int gPlayersSeen = 0;

static BOOL ToScreen(void *cam, V3 w, float sw, float sh, CGSize v, CGPoint *out) {
    V3 s = ((Fn_W2S)(gBase + RVA_CAM_W2S))(cam, w, NULL);
    if (s.z <= 0) return NO;
    out->x = s.x / sw * v.width;
    out->y = v.height - s.y / sh * v.height;           // Unity origin bottom-left -> UIKit top-left
    return YES;
}

static void UpdateWorld(CGSize v) {
    gEntN = 0;
    gPlayersSeen = 0;
    if (!gBase || !gPM) return;

    void *cam = ((Fn_Ptr0)(gBase + RVA_CAM_MAIN))(NULL);
    if (!cam) return;
    float sw = (float)((Fn_Int0)(gBase + RVA_SCR_W))(NULL);
    float sh = (float)((Fn_Int0)(gBase + RVA_SCR_H))(NULL);
    if (sw <= 0 || sh <= 0) return;

    void *camTr = ((Fn_Ptr1)(gBase + RVA_COMP_TR))(cam, NULL);
    if (!camTr) return;
    V3 camPos = ((Fn_Vec1)(gBase + RVA_TR_POS))(camTr, NULL);

    void *dict = ((Fn_Ptr1)(gBase + RVA_PM_DICT))(gPM, NULL);
    void *local = *(void **)((char *)gPM + OFF_PM_LOCAL);
    uint8_t localTeam = local ? *(uint8_t *)((char *)local + OFF_PC_TEAM) : 0;
    void *entries = dict ? *(void **)((char *)dict + OFF_DICT_ENTRIES) : NULL;
    if (!entries) return;

    int64_t len = *(int64_t *)((char *)entries + OFF_ARR_LEN);
    char *data = (char *)entries + OFF_ARR_DATA;
    float maxD = gF(@"ez.maxDist");
    BOOL enemyOnly = gB(@"ez.enemyOnly");

    for (int64_t i = 0; i < len; i++) {
        char *e = data + i * ENTRY_STRIDE;
        if (*(int32_t *)(e + 4) < -1) continue;                 // free slot
        void *pc = *(void **)(e + 0x10);
        if (!pc || pc == local) continue;
        gPlayersSeen++;
        if (gEntN >= MAX_ENTS) break;

        uint8_t team = *(uint8_t *)((char *)pc + OFF_PC_TEAM);
        BOOL enemy = (team == 1 || team == 2) && team != localTeam;
        if (enemyOnly && !enemy) continue;

        void *tr = ((Fn_Ptr1)(gBase + RVA_COMP_TR))(pc, NULL);
        if (!tr) continue;
        V3 feet = ((Fn_Vec1)(gBase + RVA_TR_POS))(tr, NULL);
        float dx = feet.x - camPos.x, dy = feet.y - camPos.y, dz = feet.z - camPos.z;
        float dist = sqrtf(dx * dx + dy * dy + dz * dz);
        if (dist > maxD) continue;

        Ent *en = &gEnts[gEntN];
        memset(en, 0, sizeof(Ent));
        en->enemy = enemy;
        en->team = team;
        en->dist = dist;
        en->fOk = ToScreen(cam, feet, sw, sh, v, &en->feet);
        V3 headFallback = { feet.x, feet.y + 1.8f, feet.z };
        en->hOk = ToScreen(cam, headFallback, sw, sh, v, &en->head);

        void *biped = *(void **)((char *)pc + OFF_PC_BIPED);
        for (int b = 0; biped && b < BN_COUNT; b++) {
            void *bt = *(void **)((char *)biped + kBoneOff[b]);
            if (!bt) continue;
            V3 bp = ((Fn_Vec1)(gBase + RVA_TR_POS))(bt, NULL);
            en->bOk[b] = ToScreen(cam, bp, sw, sh, v, &en->bones[b]);
            if (b == BN_HEAD && en->bOk[b]) en->head = en->bones[b];   // real head bone when available
            if (b == BN_HEAD && en->bOk[b]) en->hOk = YES;
        }
        gEntN++;
    }
}

// ---------------------------------------------------------------- block-based target/action
typedef void (^EzAction)(void);
static const void *kEzBlockKey = &kEzBlockKey;

@interface UIControl (EzBlock)
- (void)addBlock:(EzAction)block;
@end
@implementation UIControl (EzBlock)
- (void)addBlock:(EzAction)block {
    objc_setAssociatedObject(self, kEzBlockKey, block, OBJC_ASSOCIATION_COPY_NONATOMIC);
    UIControlEvents ev = [self isKindOfClass:[UIButton class]] ? UIControlEventTouchUpInside : UIControlEventValueChanged;
    [self addTarget:self action:@selector(ezFire) forControlEvents:ev];
}
- (void)ezFire {
    EzAction b = objc_getAssociatedObject(self, kEzBlockKey);
    if (b) b();
}
@end

// ---------------------------------------------------------------- overlay
@interface EzRoot : UIView
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIView *triggerArea;
@property (nonatomic, assign) CGPoint panelOff;   // user drag offset of the menu, from its default spot
@property (nonatomic, strong) UILabel *status;
@property (nonatomic) BOOL menuOpen;
@end

static CAShapeLayer *gBoxE, *gBoxT, *gSkel;
static NSMutableArray<CATextLayer *> *gText;
static UIWindow *gWin;
static EzRoot *gRoot;
static NSInteger gTick = 0;

static CATextLayer *TextLayerAt(NSInteger i) {
    while ((NSInteger)gText.count <= i) {
        CATextLayer *t = [CATextLayer layer];
        t.contentsScale = UIScreen.mainScreen.scale;
        t.alignmentMode = kCAAlignmentCenter;
        t.foregroundColor = UIColor.whiteColor.CGColor;
        t.shadowOpacity = 0.9;
        t.shadowOffset = CGSizeMake(0, 1);
        [gRoot.layer addSublayer:t];
        [gText addObject:t];
    }
    return gText[i];
}

static void DrawESP(void) {
    CGFloat fs = gF(@"ez.font");
    CGFloat bw = gF(@"ez.boxW"), sw = gF(@"ez.skelW");
    BOOL showBox = gB(@"ez.box"), showSkel = gB(@"ez.skel"), showInfo = gB(@"ez.info");

    UIBezierPath *pE = [UIBezierPath bezierPath], *pT = [UIBezierPath bezierPath], *pS = [UIBezierPath bezierPath];
    NSInteger textUsed = 0;
    for (int i = 0; i < gEntN; i++) {
        Ent *en = &gEnts[i];
        if (!en->fOk || !en->hOk) continue;
        CGFloat top = MIN(en->head.y, en->feet.y), bot = MAX(en->head.y, en->feet.y);
        CGFloat hgt = bot - top;
        if (hgt < 4) continue;
        CGFloat w = hgt * 0.5;
        CGFloat cx = en->feet.x;
        UIBezierPath *target = en->enemy ? pE : pT;

        if (showBox) [target appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - w / 2, top, w, hgt) cornerRadius:3]];
        if (showSkel) {
            for (int k = 0; k < (int)(sizeof(kPairs) / sizeof(kPairs[0])); k++) {
                int a = kPairs[k][0], b = kPairs[k][1];
                if (!en->bOk[a] || !en->bOk[b]) continue;
                [pS moveToPoint:en->bones[a]];
                [pS addLineToPoint:en->bones[b]];
            }
        }
        if (showInfo) {
            CATextLayer *t = TextLayerAt(textUsed++);
            t.fontSize = fs;
            t.string = [NSString stringWithFormat:@"%@ %.0fm", en->team == 1 ? @"T" : (en->team == 2 ? @"CT" : @"?"), en->dist];
            t.frame = CGRectMake(cx - 60, top - fs - 6, 120, fs + 4);
            t.hidden = NO;
        }
    }
    for (NSInteger i = textUsed; i < (NSInteger)gText.count; i++) gText[i].hidden = YES;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gBoxE.path = pE.CGPath;   gBoxE.strokeColor = PalColor(gI(@"ez.enemyColor")).CGColor; gBoxE.lineWidth = bw;
    gBoxT.path = pT.CGPath;   gBoxT.strokeColor = PalColor(gI(@"ez.teamColor")).CGColor;  gBoxT.lineWidth = bw;
    gSkel.path = pS.CGPath;   gSkel.strokeColor = PalColor(gI(@"ez.skelColor")).CGColor;  gSkel.lineWidth = sw;
    [CATransaction commit];
}

@implementation EzRoot

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;

    gBoxE = [CAShapeLayer layer]; gBoxT = [CAShapeLayer layer]; gSkel = [CAShapeLayer layer];
    for (CAShapeLayer *l in @[gBoxE, gBoxT, gSkel]) { l.fillColor = nil; l.lineJoin = kCALineJoinRound; [self.layer addSublayer:l]; }
    gText = [NSMutableArray array];

    // trigger: the white bar at the bottom. Tap toggles the menu.
    self.triggerArea = [[UIView alloc] init];
    self.triggerArea.backgroundColor = UIColor.clearColor;
    UIView *pill = [[UIView alloc] init];
    pill.tag = 77;
    pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
    pill.layer.cornerRadius = 2.5;
    [self.triggerArea addSubview:pill];
    [self.triggerArea addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)]];
    [self addSubview:self.triggerArea];

    // panel: rounded dark card, slides up from the bottom bar
    self.panel = [[UIView alloc] init];
    self.panel.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.10 alpha:0.97];
    self.panel.layer.cornerRadius = 26;
    self.panel.layer.masksToBounds = YES;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [PalColor(0) colorWithAlphaComponent:0.35].CGColor;
    self.panel.hidden = YES;
    self.panel.alpha = 0;
    [self addSubview:self.panel];
    [self buildMenuInto:self.panel];

    // grip strip on top of the menu: drag here to move the whole panel
    UIView *grip = [[UIView alloc] init];
    grip.tag = 78;
    grip.backgroundColor = UIColor.clearColor;
    UIView *gripPill = [[UIView alloc] init];
    gripPill.tag = 79;
    gripPill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
    gripPill.layer.cornerRadius = 2;
    [grip addSubview:gripPill];
    [grip addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panDrag:)]];
    [self.panel addSubview:grip];
    return self;
}

- (void)panDrag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    CGFloat x = self.panelOff.x + t.x, y = self.panelOff.y + t.y;
    self.panelOff = CGPointMake(MAX(-W / 2, MIN(W / 2, x)), MAX(-H, MIN(40, y)));
    [self setNeedsLayout];
}

- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return v == self ? nil : v;                  // everything else goes through to the game
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    CGFloat safeBottom = self.safeAreaInsets.bottom;
    // bar: 150 wide, sits 6pt above the bottom edge (or the safe area)
    self.triggerArea.frame = CGRectMake((W - 200) / 2, H - MAX(safeBottom, 4) - 28, 200, 28);
    UIView *pill = [self.triggerArea viewWithTag:77];
    pill.frame = CGRectMake(25, 28 - 6 - 5, 150, 5);

    CGFloat pw = MIN(W - 32, 380), ph = MIN(H * 0.74, 600);
    self.panel.bounds = CGRectMake(0, 0, pw, ph);
    self.panel.center = CGPointMake(W / 2 + self.panelOff.x,
                                    H - MAX(safeBottom, 14) - 46 - ph / 2 + self.panelOff.y);
    UIView *grip = [self.panel viewWithTag:78];
    grip.frame = CGRectMake(0, 0, pw, 30);
    [grip viewWithTag:79].frame = CGRectMake(pw / 2 - 22, 12, 44, 4);
}

- (void)toggleMenu {
    [self setMenuOpen:!self.menuOpen animated:YES];
}

- (void)setMenuOpen:(BOOL)open animated:(BOOL)animated {
    _menuOpen = open;
    if (open) {
        self.panel.hidden = NO;
        self.panel.transform = CGAffineTransformMakeTranslation(0, self.panel.bounds.size.height + 60);
        self.panel.alpha = 0;
    }
    CGAffineTransform t = open ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(0, self.panel.bounds.size.height + 60);
    void (^changes)(void) = ^{
        self.panel.transform = t;
        self.panel.alpha = open ? 1 : 0;
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (!self->_menuOpen) self.panel.hidden = YES;
    };
    if (animated) {
        [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseOut animations:changes completion:done];
    } else {
        changes();
        done(YES);
    }
}

// ---- menu building helpers
- (UILabel *)sectionTitle:(NSString *)s {
    UILabel *l = [[UILabel alloc] init];
    l.text = s.uppercaseString;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    l.textColor = PalColor(0);
    return l;
}

- (UIStackView *)rowWithLabel:(NSString *)title control:(UIView *)c {
    UILabel *l = [[UILabel alloc] init];
    l.text = title;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    l.textColor = [UIColor colorWithWhite:0.92 alpha:1];
    UIStackView *h = [[UIStackView alloc] initWithArrangedSubviews:@[l, c]];
    h.axis = UILayoutConstraintAxisHorizontal;
    h.alignment = UIStackViewAlignmentCenter;
    h.distribution = UIStackViewDistributionFill;
    return h;
}

- (UIView *)cardWithRows:(NSArray<UIView *> *)rows {
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:rows];
    s.axis = UILayoutConstraintAxisVertical;
    s.spacing = 12;
    s.layoutMargins = UIEdgeInsetsMake(12, 14, 12, 14);
    s.layoutMarginsRelativeArrangement = YES;
    UIView *card = [[UIView alloc] init];
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
    card.layer.cornerRadius = 16;
    [card addSubview:s];
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:card.topAnchor],
        [s.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [s.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [s.trailingAnchor constraintEqualToAnchor:card.trailingAnchor]]];
    return card;
}

- (UISwitch *)switchFor:(NSString *)key {
    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = PalColor(0);
    sw.on = gB(key);
    [sw addBlock:^{ sV(key, @(sw.on)); }];
    return sw;
}

- (UISlider *)sliderFor:(NSString *)key min:(float)mn max:(float)mx label:(UILabel *)lab fmt:(NSString *)fmt {
    UISlider *sl = [[UISlider alloc] init];
    sl.minimumValue = mn;
    sl.maximumValue = mx;
    sl.value = gF(key);
    sl.minimumTrackTintColor = PalColor(0);
    lab.text = [NSString stringWithFormat:fmt, sl.value];
    [sl addBlock:^{
        sV(key, @(sl.value));
        lab.text = [NSString stringWithFormat:fmt, sl.value];
    }];
    return sl;
}

- (UIView *)swatchesFor:(NSString *)key {
    UIStackView *s = [[UIStackView alloc] init];
    s.axis = UILayoutConstraintAxisHorizontal;
    s.spacing = 8;
    s.distribution = UIStackViewDistributionFillEqually;
    NSInteger sel = gI(key);
    for (NSInteger i = 0; i < 8; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.backgroundColor = PalColor(i);
        b.layer.cornerRadius = 11;
        b.layer.borderWidth = (i == sel) ? 2.5 : 0;
        b.layer.borderColor = UIColor.whiteColor.CGColor;
        b.tag = i;
        [b addBlock:^{
            sV(key, @(i));
            for (UIView *v in s.arrangedSubviews) {
                v.layer.borderWidth = (v.tag == i) ? 2.5 : 0;
            }
        }];
        [s addArrangedSubview:b];
        [b.heightAnchor constraintEqualToConstant:22].active = YES;
    }
    return s;
}

- (void)buildMenuInto:(UIView *)panel {
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:scroll];

    // header
    UIView *logo = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    logo.layer.cornerRadius = 12;
    logo.layer.masksToBounds = YES;
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = logo.bounds;
    g.colors = @[(id)[UIColor colorWithRed:0.56 green:0.48 blue:1 alpha:1].CGColor,
                 (id)[UIColor colorWithRed:0.25 green:0.45 blue:1 alpha:1].CGColor];
    [logo.layer addSublayer:g];
    UILabel *e = [[UILabel alloc] initWithFrame:logo.bounds];
    e.text = @"E";
    e.textAlignment = NSTextAlignmentCenter;
    e.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    e.textColor = UIColor.whiteColor;
    [logo addSubview:e];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"EzWare";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    UILabel *sub = [[UILabel alloc] init];
    sub.text = @"AngelKlear (con1xx)";
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    UIStackView *titles = [[UIStackView alloc] initWithArrangedSubviews:@[title, sub]];
    titles.axis = UILayoutConstraintAxisVertical;
    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[logo, titles]];
    head.axis = UILayoutConstraintAxisHorizontal;
    head.spacing = 12;
    head.alignment = UIStackViewAlignmentCenter;

    // ESP section
    UILabel *lblBoxW = [[UILabel alloc] init];
    lblBoxW.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    lblBoxW.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    UILabel *lblSkelW = [[UILabel alloc] init];
    lblSkelW.font = lblBoxW.font; lblSkelW.textColor = lblBoxW.textColor;
    UILabel *lblFont = [[UILabel alloc] init];
    lblFont.font = lblBoxW.font; lblFont.textColor = lblBoxW.textColor;
    UILabel *lblDist = [[UILabel alloc] init];
    lblDist.font = lblBoxW.font; lblDist.textColor = lblBoxW.textColor;

    UIView *espCard = [self cardWithRows:@[
        [self rowWithLabel:@"Boxes" control:[self switchFor:@"ez.box"]],
        [self rowWithLabel:@"Skeleton" control:[self switchFor:@"ez.skel"]],
        [self rowWithLabel:@"Team / distance" control:[self switchFor:@"ez.info"]],
        [self rowWithLabel:@"Enemies only" control:[self switchFor:@"ez.enemyOnly"]],
        [self rowWithLabel:@"Box width" control:[self sliderFor:@"ez.boxW" min:0.5 max:4 label:lblBoxW fmt:@"%.1f"]],
        lblBoxW,
        [self rowWithLabel:@"Skeleton width" control:[self sliderFor:@"ez.skelW" min:0.5 max:4 label:lblSkelW fmt:@"%.1f"]],
        lblSkelW,
        [self rowWithLabel:@"Label size" control:[self sliderFor:@"ez.font" min:8 max:18 label:lblFont fmt:@"%.0f"]],
        lblFont,
        [self rowWithLabel:@"Max distance" control:[self sliderFor:@"ez.maxDist" min:50 max:500 label:lblDist fmt:@"%.0f m"]],
        lblDist,
    ]];

    // colors section
    UIView *colorCard = [self cardWithRows:@[
        [self sectionTitle:@"Enemy box"], [self swatchesFor:@"ez.enemyColor"],
        [self sectionTitle:@"Team box"], [self swatchesFor:@"ez.teamColor"],
        [self sectionTitle:@"Skeleton"], [self swatchesFor:@"ez.skelColor"],
    ]];

    UILabel *status = [[UILabel alloc] init];
    status.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    status.textColor = [UIColor colorWithWhite:0.5 alpha:1];
    status.numberOfLines = 0;
    self.status = status;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Close" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.backgroundColor = PalColor(0);
    close.layer.cornerRadius = 14;
    [close addBlock:^{ [self setMenuOpen:NO animated:YES]; }];
    [close.heightAnchor constraintEqualToConstant:44].active = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[head, espCard, colorCard, status, close]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.layoutMargins = UIEdgeInsetsMake(20, 18, 20, 18);
    stack.layoutMarginsRelativeArrangement = YES;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
}

@end

// ---------------------------------------------------------------- driver
@interface EzTicker : NSObject
+ (void)tick:(CADisplayLink *)dl;
@end
@implementation EzTicker
+ (void)tick:(CADisplayLink *)dl {
    if (!gRoot) return;
    gTick++;
    if (gTick % 2 == 0) UpdateWorld(gRoot.bounds.size);   // world at 30 Hz, drawing every frame
    DrawESP();
    if (gRoot.menuOpen) {
        gRoot.status.text = [NSString stringWithFormat:@"players: %d   visible: %d   hook: %@   pm: %@",
                             gPlayersSeen, gEntN, gHookOK ? @"ok" : @"no", gPM ? @"yes" : @"no"];
    }
}
@end

// the window must not swallow touches that land on empty space: otherwise the game gets nothing
@interface EzWindow : UIWindow
@end
@implementation EzWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return v == self ? nil : v;
}
@end

static void SetupOverlay(void) {
    if (gWin) return;
    gWin = [[EzWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) { gWin.windowScene = (UIWindowScene *)s; break; }
    }
    gWin.windowLevel = UIWindowLevelStatusBar + 100;
    gWin.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [[UIViewController alloc] init];
    gWin.rootViewController = vc;
    gRoot = [[EzRoot alloc] initWithFrame:gWin.bounds];
    gRoot.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    vc.view = gRoot;
    gWin.hidden = NO;

    CADisplayLink *dl = [CADisplayLink displayLinkWithTarget:[EzTicker class] selector:@selector(tick:)];
    [dl addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

__attribute__((constructor)) static void EzInit(void) {
    [D registerDefaults:@{
        @"ez.box": @YES, @"ez.skel": @YES, @"ez.info": @YES, @"ez.enemyOnly": @YES,
        @"ez.enemyColor": @1, @"ez.teamColor": @2, @"ez.skelColor": @0,
        @"ez.boxW": @1.5, @"ez.skelW": @1.2, @"ez.font": @11.0, @"ez.maxDist": @150.0,
    }];
    InstallHooks();
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) { SetupOverlay(); }];
}
