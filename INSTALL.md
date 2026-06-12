# 🐶 MacPet 安装说明 / Install Instructions

> ⚠️ 第一次打开时 macOS 可能提示「已损坏」或「无法打开」——
> **这不是真的损坏！** 只是因为这个 App 没有花钱买苹果的开发者签名。
> 按下面的步骤做就能正常使用。
>
> ⚠️ macOS may say the app is **"damaged"** or "can't be opened" —
> it is NOT actually damaged! It's just unsigned (no paid Apple
> developer certificate). Follow the steps below.

## 安装步骤 / How to install

1. 把 `MacPet.app` 拖到「应用程序 / Applications」文件夹。
   Drag `MacPet.app` into your **Applications** folder.

2. 打开「终端 / Terminal」（在 启动台 → 其他 / Launchpad → Other 里），
   复制粘贴下面这一行，然后按回车：
   Open **Terminal** (Launchpad → Other → Terminal), paste this line,
   and press Return:

   ```sh
   xattr -cr /Applications/MacPet.app
   ```

3. 双击打开 MacPet —— 小狗就会出现在屏幕上啦！
   Double-click MacPet — the puppy appears on your screen!

   - 如果还是打不开：苹果菜单 → 系统设置 → 隐私与安全性 →
     拉到最下面点「仍要打开」。
   - If it still won't open: Apple menu → System Settings →
     Privacy & Security → scroll down → **"Open Anyway"**.

## 开始使用 / Getting started

- 右键点击小狗可以打开设置窗口，里面的「通用 General」标签页有完整的使用说明。
  Right-click the puppy to open Settings — the **通用 General** tab
  has the full user manual.

- App 会在每次开机登录时自动启动。
  The app starts automatically every time you log in.

## 从源码构建 / Building from source

```sh
./build.sh        # requires Xcode Command Line Tools
open MacPet.app
```

祝使用愉快！Enjoy! 🐾
