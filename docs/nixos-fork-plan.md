# TaskMan NixOS フォーク移行・公開作業手順

`aufkrawall/taskman` のフォークを NixOS 向けに対応・パッケージ化し、MIT ライセンスに則って公開するための作業手順書です。

---

## 確定方針（Phase 1 決定済み）

- **上流互換性**: Windows / macOS 向けコードはそのまま残し、上流からの取り込みを容易にする。
- **パッケージ名 / バイナリ名**: `taskman` を維持（MIT ライセンス準拠、`aufkrawall/taskman` からのフォークであることを `LICENSE` および `README.md` に明記）。
- **アプリ ID (`APP_ID`)**: `io.github.cet_t.Taskman`（Freedesktop / D-Bus / AppStream 規約に従いハイフンをアンダースコアへ変換）。
- **特権プロセス操作（Polkit ヘルパー）**: 第 2 弾へ分離。第 1 弾では `systemctl` 経由のサービス操作＋Nix パッケージ化・Flake・NixOS モジュール整備を完了する。

---

## Phase 1: 方針決定と MIT ライセンス・帰属の整備

- [x] **1. フォーク方針の確定**
  - **上流互換性**: Windows / macOS 向けコードを残す。
  - **アプリ ID / パッケージ名**: パッケージ名・バイナリ名は `taskman`、`APP_ID` は `io.github.cet_t.Taskman` とする。
  - **特権操作の範囲**: 第 1 弾は `systemctl` 経由のサービス操作＋Nix パッケージ化・NixOS モジュールまでとし、特権プロセス操作は第 2 弾へ分離する。

- [x] **2. MIT ライセンス準拠・著作権表記の確認**
  - `LICENSE` の原著作権表示（`Copyright (c) 2026 aufkrawall`）および MIT ライセンス本文を保持し、フォーク分の著作権行（`Copyright (c) 2026 cet-t (NixOS fork modifications)`）を追記。
  - ベンダー済みクレートのライセンス（`vendor/egui`: `MIT OR Apache-2.0`, `vendor/winit`: `Apache-2.0`）を保持。
  - ルート `Cargo.toml` および各クレートに `repository = "https://github.com/cet-t/taskman"` を設定。

---

## Phase 2: NixOS 固有の非互換修正（コード改修）

- [x] **3. `/nix/store` における信頼パス検証の修正**
  - `crates/tm-platform/src/linux/launch.rs`（`trust_executable()`）および `crates/tm-platform/src/fontconfig_text.rs`（`trusted_path_chain()`）で、厳密に `/nix/store` ルートに限って `uid == 0 && sticky && !world_writable`（`0o1775`）を許可しつつ、store エントリ配下およびバイナリ本体は従来の厳格ルールを維持。
  - ビルド時パス注入（`TASKMAN_FC_MATCH_PATH`, `TASKMAN_SYSTEMCTL_PATH`, `TASKMAN_LOGINCTL_PATH`, `TASKMAN_PKEXEC_PATH`）に対応。

- [x] **4. FHS ハードコードパスの NixOS 対応 & Linux テスト/Lint 修正**
  - `systemctl`・`loginctl` の探索候補に `/run/current-system/sw/bin/` を追加、`pkexec` は `/run/wrappers/bin/pkexec` を最優先化。
  - `xdg_icons.rs` で `<data_dir>/pixmaps/` を探索対象に追加。
  - `autostart.rs` で `/nix/store/` 配下実行時に安定プロファイルラッパー（`~/.nix-profile/bin/taskman`, `/etc/profiles/per-user/$USER/bin/taskman`, `/run/current-system/sw/bin/taskman`）や `TASKMAN_AUTOSTART_EXEC` を優先。
  - `linux/mod.rs` の `hostname()` に `/proc/sys/kernel/hostname` フォールバックを追加。
  - 上流で未実行だった Linux 専用テスト・clippy 警告を修正（`drm.rs`, `process_connections.rs`, `polkit.rs`, `app_history.rs`, `activation.rs`, `desktop_session.rs`）。

- [x] **5. （第 2 弾）NixOS 向け保護済み特権ヘルパー連携**
  - GUI 依存を持たない軽量な専用特権ヘルパーバイナリ `taskman-privileged-helper`（`crates/tm-platform/src/bin/taskman-privileged-helper.rs`、`$out/libexec/` へ素の ELF のまま配置）と Polkit ポリシー `packaging/linux/io.github.cet_t.Taskman.policy.in`（`allow_gui=false`）を実装。
  - `programs.taskman.enablePrivilegedHelper`（既定 `true`）および Flake 契約テスト（`privileged-helper-contract`, `nixos-module`）を追加。

---

## Phase 3: Nix パッケージング・Flake・NixOS モジュール作成

- [x] **6. Nix Flake（`flake.nix` / `flake.lock` / `nix/package.nix`）の作成**
  - `nixpkgs-unstable` 単独入力で `rustPlatform.buildRustPackage` によりオフラインビルド可能に構成。
  - `TASKMAN_FC_MATCH_PATH` / `TASKMAN_SYSTEMCTL_PATH` / `TASKMAN_LOGINCTL_PATH` を store パスにピン留め。
  - Wayland / X11 / Vulkan / OpenGL 動的ライブラリおよび `xdg-utils` を `wrapProgram` で自動ラップ。
  - `packaging/linux/io.github.cet_t.Taskman.desktop` を `$out/share/applications/` へ配置。

- [x] **7. Flake 出力の拡充**
  - `packages.{x86_64-linux,aarch64-linux}.{taskman,default}`
  - `apps.<system>.default`
  - `overlays.default`
  - `nixosModules.{taskman,default}`（`nix/nixos-module.nix`）
  - `homeManagerModules.{taskman,default}`（`nix/home-manager-module.nix`）
  - `devShells.<system>.default`
  - `checks.<system>.{package,selfcheck-mock}`

---

## Phase 4: テスト・CI・ドキュメント・公開準備

- [x] **8. 回帰テストと動作検証**
  - NixOS 信頼パス検証・autostart 安定パス・`data_dir/pixmaps` の回帰テストを追加。
  - `cargo fmt --all -- --check`、`cargo clippy` (`-D warnings`)、`cargo test`（668 passed）、`nix flake check`、`nix build`、実機 `./result/bin/taskman --selfcheck` を通過。
  - [x] 実機 GUI での目視確認（Wayland タブ切り替え時の `softbuffer` 残像修正を含む）。

- [x] **9. CI の更新**
  - `.github/workflows/ci.yml` に `nix flake check` ジョブおよび Linux Rust ゲートを追加（上流 Windows ゲートも維持）。

- [x] **10. ドキュメントと CHANGELOG の更新**
  - `README.md` を NixOS フォーク向けに刷新（上流クレジット・MIT ライセンス・導入手順・制約明記）。
  - `CHANGELOG.md` の `Unreleased` セクションに NixOS 向け変更を記録。

- [x] **11. 公開前チェック**
  - ライセンス・著作権ファイル確認、シークレット漏洩チェック（コミット前後）、Git LFS ポインタ混入チェックを実施。
