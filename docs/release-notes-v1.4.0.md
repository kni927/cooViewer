# cooViewer v1.4.0 — Release Notes (draft)

## Changed

- **Archive engine replaced.** The XADMaster / UniversalDetector
  submodules have been replaced with
  [libarchive](https://www.libarchive.org/) +
  [uchardet](https://www.freedesktop.org/wiki/Software/uchardet/)
  (bundled as universal dylibs) for long-term maintainability.
  Extraction of ZIP/CBZ, RAR/CBR (including RAR5), 7z, and TAR has
  been verified **byte-identical to v1.3.7** across 800+ entries /
  700+ MB of real archives.
- Faster solid-7z extraction; large archives show progress and the
  open can be cancelled with Esc.
- Japanese (CP932/Shift_JIS) filenames in legacy ZIPs keep working —
  encoding detection now runs archive-wide via uchardet.

## Removed

- **LhA/LZH and StuffIt archives.** Use
  [v1.3.7](https://github.com/kni927/cooViewer/releases/tag/v1.3.7)
  (the final release with the old engine) or convert to ZIP.
- **Password-protected archives.** Also last supported in v1.3.7.
- Multi-volume archives (`.z01`, `.r00`…) and the long tail of
  exotic formats (cab, arj, ace, Amiga disk images, …) are no longer
  registered file types.

## Internal

- XADMaster / UniversalDetector submodules removed; the project now
  builds with `vendor/build-libs.sh` + `xcodebuild` (no submodules).

---

## 変更

- **アーカイブエンジンを置き換えました。** 長期的なメンテナンス性の
  ため、XADMaster / UniversalDetector サブモジュールを libarchive +
  uchardet(ユニバーサル dylib として同梱)に置き換えました。
  ZIP/CBZ・RAR/CBR(RAR5 含む)・7z・TAR の展開結果は
  **v1.3.7 とバイト単位で一致**することを確認済みです(実書庫
  800 以上のエントリ / 700MB 超で検証)。
- ソリッド 7z の展開が高速化。大きな書庫では読み込み中に Esc で
  キャンセルできます。
- レガシー ZIP の日本語ファイル名(CP932/Shift_JIS)は引き続き
  正しく表示されます(uchardet による書庫全体での判定)。

## 廃止

- **LhA/LZH・StuffIt 書庫。** 旧エンジン最終版の
  [v1.3.7](https://github.com/kni927/cooViewer/releases/tag/v1.3.7)
  をご利用いただくか、ZIP への変換をお願いします。
- **パスワード付き書庫。** こちらも v1.3.7 が最終対応版です。
- マルチボリューム書庫(`.z01`、`.r00`…)およびレガシー形式の
  ロングテール(cab、arj、ace、Amiga ディスクイメージ等)は
  関連付けから外れました。

**Full Changelog**: https://github.com/kni927/cooViewer/compare/v1.3.7...v1.4.0
