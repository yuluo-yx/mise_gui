# Scripts

这个目录下主要是 macOS 打包脚本。现在根目录已经加了 `package.json`，可以直接通过 `npm run` 调用，不需要记具体脚本文件名。

## 常用命令

```bash
npm run help
npm run macos:dmg:background
npm run macos:dmg:background:2x
npm run macos:debug:dmg
npm run macos:release:app
npm run macos:release:dmg
npm run macos:release:zip
```

## 跳过公证

如果你只想本地快速出包验证，不走 Apple notarization，可以用这些命令：

```bash
npm run macos:release:app:skip-notarization
npm run macos:release:dmg:skip-notarization
npm run macos:release:zip:skip-notarization
```

## 每个脚本做什么

- `macos:dmg:background`
  生成 DMG 背景图，默认输出到 `packaging/macos/dmg-background.png` 和 `packaging/macos/dmg-background@2x.png`
- `macos:debug:dmg`
  构建 debug 版 macOS app，并打成调试用 DMG
- `macos:release:app`
  构建 release 版 `.app`，签名、公证、staple 后输出到 `dist/macos/`
- `macos:release:dmg`
  构建 release 版 `.dmg`，签名、公证、staple 后输出到 `dist/macos/`
- `macos:release:zip`
  构建 release 版 `.zip`，先提交 zip 做公证，再对 app staple，最后重新打成最终 zip

## 可用环境变量

这些变量可以在执行前临时传入：

```bash
SIGNING_IDENTITY="Developer ID Application: NAME (TEAMID)" \
NOTARY_PROFILE="mise-gui-notary" \
npm run macos:release:dmg
```

- `SIGNING_IDENTITY`
  覆盖默认签名证书。不传时会自动选择第一个可用的 `Developer ID Application`
- `NOTARY_PROFILE`
  覆盖 `xcrun notarytool` 使用的 keychain profile，默认是 `mise-gui-notary`
- `SKIP_NOTARIZATION`
  只在对应的 `:skip-notarization` npm script 里预先设置为 `1`

## 输出目录

默认产物都放在：

```bash
dist/macos/
```
