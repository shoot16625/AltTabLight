# AltTabLight

[AltTab](https://alt-tab.app/) から不要機能を削ぎ落とした軽量版。ウインドウスイッチャー(サムネイル表示・プレビュー)とショートカットキー設定のみを残しています。

- 動作要件: macOS 13 以降
- ビルドサイズ: Debug 約5MB / Release 約3MB
- アイドル時メモリ: フットプリント約22MB

## ビルド方法

`xcodebuild` が使える環境(Command Line Tools のみでも可)が必要です。

```sh
# Debug ビルド(開発用)
bash ai/build.sh
# → DerivedData/Build/Products/Debug/AltTabLight.app

# Release ビルド(小さくて軽い)
xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -configuration Release -derivedDataPath DerivedData build
# → DerivedData/Build/Products/Release/AltTabLight.app
```

個人利用のため署名は ad-hoc です(`config/local.xcconfig` の `CODE_SIGN_IDENTITY = -`)。自分でビルドしたアプリには Gatekeeper の検証は走らないので、そのまま起動できます。

## インストールと初回設定

1. ビルドした `AltTabLight.app` を `/Applications` にコピーし、ダブルクリックで起動
2. 初回起動時に設定ウインドウが開くので、ショートカットキーを設定(既定は「⌥ を押しっぱなし + Tab」)
3. システム設定 → プライバシーとセキュリティで許可を付与:
   - アクセシビリティ(必須:ウインドウ操作のため)
   - 画面収録(サムネイル・プレビュー表示のため)

## 使い方

設定したショートカットを押しっぱなしにするとスイッチャーが表示されます。

- Tab / 矢印キー: 選択移動(前へは ⇧Tab)
- ⌘W: 選択中ウインドウを閉じる、⌘M: 最小化、⌘F: 全画面、⌘Q: 終了、⌘H: 隠す
- ショートカットから手を離す: 選択中ウインドウにフォーカス

## 補足

- バンドル ID: `com.lwouis.alt-tab-light`(dev ビルドは `com.lwouis.alt-tab-light.dev`)。設定は UserDefaults に保存され、バンドル ID を変えると設定が初期化されます
- ライセンス: MIT(本家 AltTab 由来の `LICENCE.md` を引き継ぎ)

## 開発メモ

- `ai/build.sh` が唯一のビルドコマンド。ソースファイルを追加・削除した場合は `alt-tab-macos.xcodeproj/project.pbxproj` の手動更新が必要
- コミットは conventional-commits 形式(`fix:` / `feat:` 等、小文字始まり)が commitlint で強制されます
