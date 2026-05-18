# StarChat App UI 重新设计方案

> **设计风格**：梦幻马卡龙 (Dreamy Macaron)
> **创建日期**：2026-04-13
> **目标**：全部页面重新设计

---

## 一、色彩系统

### 1.1 核心色板

| 角色 | 色值 | 色名 | 用途 |
|---|---|---|---|
| **主色 Primary** | `#FF6B9D` | 玫粉 | 按钮、Tab选中、进度条、强调 |
| **主色渐变 Start** | `#FF6B9D` | 玫粉 | 渐变起点 |
| **主色渐变 End** | `#C9A7EB` | 薰衣草紫 | 渐变终点 |
| **薄荷辅色 Secondary** | `#7DD3C0` | 薄荷绿 | 成功状态、在线标识、余额卡片 |
| **薄荷深色** | `#5FBFAA` | 深薄荷 | Secondary pressed |
| **薰衣草 Accent** | `#C9A7EB` | 薰衣草紫 | 渐变搭配、装饰元素 |
| **背景色 Background** | `#FFF9F5` | 奶油白 | 全局Scaffold背景 |
| **卡片 Surface** | `#FFFFFF` | 纯白 | 卡片、弹窗、输入框背景 |
| **文字 Primary** | `#2D2D2D` | 深灰 | 标题、正文 |
| **文字 Secondary** | `#8B7E7E` | 中灰 | 副标题、辅助说明 |
| **文字 Hint** | `#BDBDBD` | 浅灰 | 占位符、禁用态 |
| **错误色 Error** | `#FF7B7B` | 珊瑚红 | 错误提示、挂断按钮 |
| **警告色 Warning** | `#FFB74D` | 橙色 | 警告提示 |
| **分隔线** | `#F0F0F0` | 浅灰线 | Divider |

### 1.2 渐变组合

```dart
// 主按钮渐变
LinearGradient(
  colors: [Color(0xFFFF6B9D), Color(0xFFC9A7EB)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
)

// 余额卡片渐变
LinearGradient(
  colors: [Color(0xFF7DD3C0), Color(0xFF5FBFAA)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
)
```

---

## 二、字体系统

### 2.1 字号层级

| 层级 | 字号 | 字重 | 行高 | 用途 |
|---|---|---|---|---|
| Display | 28px | Bold (700) | 1.3 | 欢迎语、首页大标题 |
| Headline | 22px | SemiBold (600) | 1.3 | 页面标题 |
| Title | 18px | SemiBold (600) | 1.4 | 卡片标题、主播名 |
| Body Large | 16px | Regular (400) | 1.5 | 正文内容 |
| Body | 15px | Regular (400) | 1.5 | 正文 |
| Label | 13px | Medium (500) | 1.4 | 标签、价格、状态 |
| Caption | 11px | Regular (400) | 1.3 | 辅助说明、时间 |

### 2.2 字体方案

```yaml
fontFamily: 'Noto Sans SC'  # 中文圆润友好
```

---

## 三、圆角与间距系统

### 3.1 圆角规范

| 元素 | 圆角半径 |
|---|---|
| 页面 | 0 (撑满) |
| 卡片 | 20px |
| 按钮 | 全圆角 (height/2) 或 16px |
| 输入框 | 14px |
| 标签/徽章 | 8px |
| 头像 | 圆形 (radius = size/2) |

### 3.2 间距规范 (4dp 基础单位)

| 名称 | 数值 | 用途 |
|---|---|---|
| xs | 4px | 紧凑间距 |
| sm | 8px | 图标文字间距 |
| md | 12px | 卡片内边距 |
| lg | 16px | 区块间距 |
| xl | 24px | 区块组间距 |
| xxl | 32px | 页面大间距 |
| xxxl | 48px | 页面顶部间距 |

---

## 四、阴影与质感

### 4.1 阴影规范

```dart
// 卡片悬浮阴影（淡粉色光晕）
BoxShadow(
  color: Color(0xFFFF6B9D).withValues(alpha: 0.08),
  blurRadius: 20,
  offset: Offset(0, 4),
)

// 按钮按下阴影
BoxShadow(
  color: Color(0xFFFF6B9D).withValues(alpha: 0.15),
  blurRadius: 32,
  offset: Offset(0, 8),
)
```

---

## 五、页面设计方案

### 5.1 Splash 页面 (splash_page.dart)

**当前状态**：玫红纯色背景 + 白色Logo文字

**设计方案**：
- 背景：奶油白 `#FFF9F5`
- 中央装饰：淡粉色圆形/圆环无序散布（装饰性背景元素）
- Logo容器：渐变背景 (玫粉→薰衣草)，白色心形图标
- App名称：渐变文字 (玫粉→薰衣草)
- 副标题：淡灰色 `#8B7E7E`

```dart
// Logo 容器渐变
BoxDecoration(
  gradient: LinearGradient(
    colors: [Color(0xFFFF6B9D), Color(0xFFC9A7EB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  borderRadius: BorderRadius.circular(28),
)
```

---

### 5.2 登录页面 (login_page.dart)

**当前状态**：白色背景 + 基础输入框 + 玫红按钮

**设计方案**：
- 背景：奶油白 `#FFF9F5` + 淡粉色圆形装饰元素（左下/右上）
- Logo区：渐变心形图标 (玫粉→薰衣草)
- 标题：深灰 `#2D2D2D`，22px bold
- 副标题：淡灰色 `#8B7E7E`
- 输入框：
  - 背景：白色 `#FFFFFF`
  - 边框：1px 浅灰 `#F0F0F0`
  - 聚焦边框：2px 玫粉 `#FF6B9D`
  - 圆角：14px
  - 左侧图标：淡灰色
- 登录按钮：
  - 背景：渐变 (玫粉→薰衣草)
  - 高度：56px
  - 圆角：28px (全圆角)
  - 文字：白色，16px bold
- 开发期提示：薄荷绿背景 `#7DD3C0` + 白色文字

---

### 5.3 底部导航 (main_shell.dart)

**当前状态**：白色背景 + 基础BottomNavigationBar

**设计方案**：
- 导航栏背景：白色 + 毛玻璃效果
- 选中态：图标和文字均为玫粉 `#FF6B9D`
- 未选中态：淡灰色 `#8B7E7E`
- 中间通话按钮：
  - 圆形突出，玫粉渐变背景
  - 放大效果 (高度大于其他item)
  - 白色电话图标

```dart
// 导航栏毛玻璃背景
Container(
  decoration: BoxDecoration(
    color: Colors.white.withValues(alpha: 0.9),
    boxShadow: [
      BoxShadow(
        color: Color(0xFFFF6B9D).withValues(alpha: 0.05),
        blurRadius: 20,
        offset: Offset(0, -4),
      ),
    ],
  ),
)
```

---

### 5.4 首页 (home_page.dart)

**当前状态**：网格瀑布流 + 顶部余额徽章 + 基础一键速配按钮

**设计方案**：
- AppBar：
  - 背景：白色 + 底部淡粉色分隔线
  - 标题：深灰 "StarChat"，22px bold
  - 右侧余额徽章：玫粉渐变背景，白色文字/钱包图标
- 一键速配按钮：
  - 高度：56px
  - 背景：渐变 (玫粉→薰衣草)
  - 圆角：28px
  - 图标：白色闪电图标
  - 文字：白色，16px bold
- 主播卡片：
  - 背景：白色
  - 圆角：20px
  - 阴影：淡粉色光晕
  - 头像区：圆形裁剪，顶部圆角
  - 在线状态标签：薄荷绿背景 (在线) / 灰色 (离线)
  - 价格标签：黑色半透明背景，圆角8px
  - 底部信息区：主播名 (18px) + 简介 (13px淡灰)

---

### 5.5 通话标签页 (call_page.dart)

**当前状态**：基础Icon + 文字 + 跳转按钮

**设计方案**：
- 页面背景：奶油白 `#FFF9F5`
- 中央大图标：玫粉渐变空心圆包裹
- 标题：深灰 "暂无通话记录"，16px
- 副标题：淡灰 "去首页找一个主播开始通话吧"
- 跳转按钮：
  - 边框样式，玫粉边框
  - 文字：玫粉

---

### 5.6 通话房间页 (call_room_page.dart)

**当前状态**：纯黑背景 + 白色图标控制栏

**设计方案**：
- 整体换肤：黑色背景 → **淡粉渐变背景** 或 **深色毛玻璃**
  - 方案A：淡粉渐变背景 `Color(0xFF1A1A1A)` → `Color(0xFF2D1F2F)`
  - 方案B：毛玻璃效果 + 淡粉色光晕
- 顶部状态栏：
  - 毛玻璃背景
  - 标题：白色，16px bold
  - 计时：白色70%
- 控制按钮区：
  - 毛玻璃背景
  - 按钮圆形：白色12%背景 + 白色图标
  - 挂断按钮：珊瑚红 `#FF7B7B`
- 本地预览窗口：
  - 圆角：12px
  - 边框：1px 白色24%

---

### 5.7 个人资料页 (profile_page.dart)

**当前状态**：渐变余额卡片 + 列表菜单

**设计方案**：
- AppBar：白色背景，深灰标题
- 头像区：
  - 头像：72px圆形，玫粉渐变底座装饰
  - 昵称：22px bold
  - ID：淡灰色
- 余额卡片：
  - 背景：渐变 (薄荷绿 #7DD3C0 → 深薄荷 #5FBFAA)
  - 图标：白色
  - 金额：白色28px bold
  - 充值按钮：白色文字，薄荷绿背景，圆角20px
- 功能菜单：
  - 卡片承载，圆角16px
  - 图标：圆形玫粉/薄荷绿背景
  - 标题：深灰
  - 右侧： chevron_right
- 退出登录：
  - 边框样式，珊瑚红边框和文字

---

### 5.8 礼物面板 (gift_panel.dart)

**当前状态**：白色弹窗 + 玫红选中态

**设计方案**：
- 弹窗顶部：拖动条改为淡粉色
- 标题：深灰 "发送礼物"
- 余额徽章：薄荷绿背景，白色文字
- 礼物网格：
  - 卡片背景：薄荷绿10%背景 (选中) / 灰色5% (未选)
  - 边框：2px 薄荷绿 (选中)
  - 图标：薄荷绿
  - 名字：薄荷绿 (选中) / 淡灰
  - 价格：薄荷绿
- 数量选择器：薄荷绿边框
- 快捷数量：薄荷绿标签
- 发送按钮：渐变背景，厚56px

---

### 5.9 充值页面 (recharge_page.dart)

**当前状态**：网格套餐 + 支付方式列表

**设计方案**：
- 页面背景：奶油白
- 充值说明：薄荷绿背景10% + 薄荷绿文字/图标
- 套餐卡片：
  - 圆角：16px
  - 边框：1px 浅灰 (未选) / 2px 薄荷绿 (选中)
  - 金额：深灰18px bold (选中薄荷绿)
  - 标签：玫粉/薄荷绿/橙色等
- 支付方式：
  - 卡片承载，图标和文字
  - 选中态：薄荷绿边框 + check图标
- 底部按钮：
  - 渐变背景，56px高

---

### 5.10 IM 聊天页面 (im_page.dart)

**当前状态**：基础聊天气泡 + 白色输入框

**设计方案**：
- 页面背景：奶油白
- 气泡：
  - 自己：玫粉渐变背景，白色文字
  - 对方：白色背景，深灰文字，粉色左边圆角
- 时间：淡灰色
- 输入框：
  - 背景：白色
  - 圆角：24px (全圆角)
  - 发送按钮：玫粉渐变圆形

---

### 5.11 设置页面 (settings_page.dart)

**当前状态**：基础ListTile列表

**设计方案**：
- 页面背景：奶油白
- 分组标题：淡灰色，13px
- 设置项：
  - 白色卡片承载
  - 图标：圆形玫粉/薄荷绿背景
  - 标题：深灰15px
  - Switch：玫粉轨道
- 版本信息：淡灰色

---

## 六、组件规范

### 6.1 按钮组件

```dart
// 主按钮（渐变）
ElevatedButton.styleFrom(
  backgroundColor: Colors.transparent,  // 用Container实现渐变
  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(28),  // 高度56时全圆角
  ),
)

// 边框按钮
OutlinedButton.styleFrom(
  foregroundColor: primaryColor,
  side: BorderSide(color: primaryColor),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(20),
  ),
)
```

### 6.2 输入框组件

```dart
InputDecorationTheme(
  filled: true,
  fillColor: Colors.white,
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: Color(0xFFF0F0F0)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: Color(0xFFF0F0F0)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: primaryColor, width: 2),
  ),
)
```

### 6.3 卡片组件

```dart
BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  boxShadow: [
    BoxShadow(
      color: Color(0xFFFF6B9D).withValues(alpha: 0.08),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ],
)
```

### 6.4 标签/徽章组件

```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: Color(0xFFFF6B9D),  // 或薄荷绿/薰衣草紫
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(...),
)
```

---

## 七、实现优先级

### Phase 1: 核心组件（优先）
1. 色彩系统更新 (app_theme.dart)
2. Splash 页面
3. 登录页面
4. 底部导航

### Phase 2: 主要业务页面
5. 首页
6. 个人资料页
7. 通话房间页

### Phase 3: 功能页面
8. 礼物面板
9. 充值页面
10. IM 聊天页
11. 设置页面

---

## 八、文件修改清单

| 页面 | 文件路径 | 修改内容 |
|---|---|---|
| 主题配置 | `lib/app/theme/app_theme.dart` | 更新色彩常量 + ThemeData |
| Splash | `lib/modules/auth/splash_page.dart` | 渐变Logo + 奶油白背景 |
| 登录 | `lib/modules/auth/login_page.dart` | 新样式 + 渐变按钮 |
| 导航 | `lib/modules/home/main_shell.dart` | 毛玻璃 + 渐变中间按钮 |
| 首页 | `lib/modules/home/home_page.dart` | 渐变按钮 + 新卡片样式 |
| 通话Tab | `lib/modules/home/call_page.dart` | 新样式 |
| 通话房间 | `lib/modules/call/call_room_page.dart` | 深色渐变主题 |
| 资料页 | `lib/modules/home/profile_page.dart` | 新卡片 + 菜单样式 |
| 礼物面板 | `lib/modules/gift/gift_panel.dart` | 薄荷绿主题 |
| 充值 | `lib/modules/profile/recharge_page.dart` | 新套餐样式 |
| IM聊天 | `lib/modules/im/im_page.dart` | 新气泡样式 |
| 设置 | `lib/modules/settings/settings_page.dart` | 新列表样式 |

---

## 九、注意事项

1. **兼容性**：渐变背景需要考虑低端机性能，必要时提供降级方案
2. **一致性**：所有页面需统一使用本规范定义的颜色和圆角
3. **动效**：按钮点击使用 scale 0.95 回弹，无需复杂动效
4. **加载态**：ProgressIndicator 使用主色调颜色