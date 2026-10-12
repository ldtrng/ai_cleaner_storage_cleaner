# Phát hành AI Cleaner lên Google Play

Package: `io.ld2t.ai_cleaner` · minSdk 29 (Android 10) · targetSdk 36 · version 1.0.0 (1)

## 1. File cần upload

| File | Dùng cho |
|---|---|
| `build/app/outputs/bundle/release/app-release.aab` | Bản phát hành (Production / Internal testing) |
| `store/icon-512.png` | App icon 512×512 |
| `store/feature-graphic.png` | Feature graphic 1024×500 |
| `store/screenshots/01.png … 08.png` | 8 ảnh chụp màn hình điện thoại (1080×2160) — xem `store/ASO.md` §6 |

Build lại khi đổi code:

```bash
flutter build appbundle --release
```

Mỗi lần upload bản mới phải tăng số sau dấu `+` trong `pubspec.yaml` (`version: 1.0.1+2`).

## 2. Khoá ký (QUAN TRỌNG)

- `android/upload-keystore.jks` + `android/key.properties` (chứa mật khẩu) đã được tạo và **đã nằm trong .gitignore**.
- Sao lưu cả hai file vào nơi an toàn (password manager / ổ riêng). Mất file này thì phải xin Google reset upload key.
- Khi tạo app trên Play Console, bật **Play App Signing** (mặc định) — Google giữ app signing key, file trên chỉ là upload key.

## 3. Trước khi gửi duyệt — cần thay

Privacy policy & terms nằm trong repo, GitHub hiển thị trực tiếp (app mở các link này từ Settings):
- Privacy policy: https://ldtrng.github.io/ai_cleaner_storage_cleaner/privacy-policy.html ← dán link này vào Play Console
- Terms of use: https://ldtrng.github.io/ai_cleaner_storage_cleaner/terms.html
- Repo phải để **public** thì link mới mở được. Sửa nội dung → commit & push là link tự cập nhật.
- Email hỗ trợ: `ldtrong258@gmail.com` (`lib/core/config.dart`).

## 4. Store listing (gợi ý)

> ⚠️ **KHÔNG dùng chữ "free" (free up, free trial…) trong bất kỳ metadata store nào** (title, short/full description, feature graphic, screenshot, video). Đã dính giới hạn phân phối vì "free up storage" trong short description. Chi tiết: `store/ASO.md` §10. Copy chuẩn nằm ở `store/listing/*.txt`; đoạn dưới chỉ là bản rút gọn.

**App name:** AI Cleaner – Storage Cleaner
**Short description (≤80):** Delete duplicate photos, merge contacts, compress videos & reclaim storage.

**Full description:**

> Clear phone storage in a few taps. AI Cleaner scans your gallery on-device to find duplicate, similar and blurry photos, screenshots, screen recordings and short clips, and suggests the best shot to keep.
>
> • Smart Clean – review everything that can be cleaned in one place
> • Photos – similar, duplicate, screenshots, blurry
> • Videos – duplicates, screen recordings, short recordings
> • Compress – shrink large photos and videos with High / Medium / Low quality
> • Contacts – merge duplicates, remove incomplete entries, local backups & restore
> • Events – delete old calendar events
> • App Manager – find large and unused apps
> • Secret Space – hide photos, videos and contacts behind a PIN or fingerprint
> • Light & dark themes
>
> All cleaning runs on your device: no account needed, and your photos, contacts and calendar never leave your phone. Contains ads. Deleted media goes to the system Trash for 30 days (configurable).

**Category:** Tools · **Contact email:** (email hỗ trợ) · **Privacy policy:** (URL ở bước 3)

## 5. App content (Play Console → Policy → App content)

**Data safety** (do có AdMob — khai theo hướng dẫn của Google cho Mobile Ads SDK):
- Data collected & shared: **Yes**, mục đích *Advertising or marketing*, *Analytics*, *Fraud prevention* (AdMob + Firebase Analytics)
  - Location → *Approximate location* (từ IP)
  - App activity → *App interactions*
  - App info and performance → *Crash logs*, *Diagnostics*
  - Device or other IDs → *Device or other IDs* (Advertising ID, App set ID)
- Encrypted in transit: **Yes** · User can request deletion: **No** (dữ liệu do Google xử lý) · Collection is required.
- Ảnh, video, danh bạ, lịch chỉ xử lý trên máy → **không** khai.
- Manifest đã có `com.google.android.gms.permission.AD_ID` (SDK tự merge) → mục *Advertising ID* trong App content chọn **Yes, for advertising**.

**Ads:** **Yes, contains ads** · **Target audience:** 18+ (hoặc 13+) · **Content rating:** làm bảng hỏi IARC → "Utility".

**Photo and video permissions declaration** (bắt buộc vì dùng `READ_MEDIA_IMAGES/VIDEO`):
> Core functionality: AI Cleaner is a storage cleaner. It needs broad read access to the user's photo and video library to detect duplicate, similar and blurry photos, screen recordings and large files across the entire gallery, and to compress or move them to Trash at the user's request. The Android photo picker cannot be used because the analysis must run over the whole library, not a user-picked subset.

**Usage access (`PACKAGE_USAGE_STATS`)** — dùng cho App Manager (dung lượng & lần dùng cuối). Không phải permission bị hạn chế của Play nhưng reviewer có thể hỏi; nêu rõ trong mô tả.

**Contacts / Calendar** — không thuộc nhóm hạn chế; mô tả mục đích trong listing là đủ.

Không dùng: `MANAGE_EXTERNAL_STORAGE`, `QUERY_ALL_PACKAGES`, `REQUEST_INSTALL_PACKAGES` (để tránh bị từ chối).

## 6. Firebase

Project `ai-cleaner-333d3` (AI Cleaner), app Android `io.ld2t.ai_cleaner`.
- **Analytics** — sự kiện: `scan_complete`, `clean_complete` (source: photos / videos / smart_clean / contacts_merge / contacts_delete / events / apps), `compress_complete`, `secret_space_add`, `onboarding_complete`, `screen_view` tự động cho mọi màn hình.
- **Remote Config** — 10 tham số điều khiển quảng cáo + ngưỡng ảnh mờ, mẫu ở `docs/remote-config.json`, mặc định trong `lib/core/firebase.dart`. Đổi giá trị trên console → Publish là app nhận trong ≤1 giờ (debug: 1 phút).
- Cần file `android/app/google-services.json` (tải ở Project settings → Your apps). Không có file này app vẫn build/chạy nhưng không gửi Analytics / không lấy Remote Config.

## 6b. Quảng cáo (AdMob)

App ID và ad unit thật nằm trong `lib/ads/ads_service.dart` + `AndroidManifest.xml`. Bản debug/profile **tự dùng test ad unit của Google** (`kReleaseMode`), chỉ bản release mới dùng ID thật — không bấm quảng cáo trên bản release của chính mình.

| Loại | Vị trí | Tần suất |
|---|---|---|
| Banner (adaptive, neo đáy) | Màn hình Home | Luôn hiện ở Home; không đặt ở màn có nút Clean/Delete |
| Native (template nhỏ) | Màn hình "Congratulations" sau khi dọn | 1 lần mỗi màn, nằm trên dòng ghi chú, cách xa nút "Great!" |
| Interstitial | Khi bấm "Great!" thoát màn Congratulations | Tối đa 1 lần/3 phút, bỏ qua lần dọn đầu tiên, không bao giờ chen giữa lúc quét/xoá/nén |
| App Open | Mở app (cold start) sau lần đầu; quay lại app sau ≥4 phút ở nền | Chờ tối đa 3s ở splash; không hiện ở lần mở đầu tiên (onboarding), không hiện khi quay về từ hộp thoại hệ thống/Settings/gỡ app/share, cách ad toàn màn hình khác ≥60s |

**Việc cần làm trên AdMob:**
1. *Privacy & messaging* → tạo **GDPR message** (và US state message nếu muốn) cho app — không có message thì form consent UMP sẽ không hiện cho người dùng EEA/UK. App đã gọi UMP và có mục *Settings → Privacy settings* khi bắt buộc.
2. Sau khi app lên Play: link app với Play Store trong AdMob, và đặt file `app-ads.txt` ở **gốc domain developer website** (khai trong Play Console) với nội dung:
   ```
   google.com, pub-2822978318382771, DIRECT, f08c47fec0942fa0
   ```

## 7. Rủi ro duyệt cần biết

- **Tên/thương hiệu:** "AI Cleaner" trùng tên app gốc trên Play. Google có thể gỡ vì *impersonation* hoặc *keyword spam* nếu bị khiếu nại. Đổi tên chỉ cần sửa `appName` trong `lib/main.dart` và `android:label` trong `AndroidManifest.xml`.
- **Claims:** không quảng cáo kiểu "tăng tốc 50%", "diệt virus" — Play từ chối với app cleaner có tuyên bố gây hiểu lầm. Listing ở trên đã tránh.
- Tài khoản dev cá nhân mới (sau 11/2023) phải **closed testing với ≥12 tester trong 14 ngày** trước khi lên Production.
