# خروجی HTML برای ADRها

این بسته یک ابزار آفلاین برای ساخت یک فایل HTML مستقل و راست‌چین از فایل‌های Markdown تصمیم‌هاست. منبع فقط پوشهٔ داده‌شده است؛ فایل‌ها و `README.md` تغییر نمی‌کنند. فایل HTML شامل CSS و JavaScript داخلی است و هیچ فونت/منبع اینترنتی ندارد.

## نصب در مخزن

۱. شاخهٔ پیشنهادی بسازید: `git switch -c feature/adr-html-export` (اختیاری).
۲. محتویات این بسته را در ریشهٔ مخزن کپی کنید: `export-adr.ps1`، `install-adr-export.ps1` و پوشهٔ `tests`؛ فایل‌های `docs` و `example` نمونه/راهنما هستند.
۳. در PowerShell 7 از ریشه اجرا کنید:

```powershell
./install-adr-export.ps1
./adr.ps1 -ExportHtml
./adr.ps1 -ExportHtml -OutPath ./artifacts/adr-site/index.html -SiteTitle 'تصمیم‌های معماری پروژه'
./adr.ps1 -ExportHtml -OutPath ./artifacts/adr-en/index.html -SiteTitle 'Architecture Decisions' -Language en
```

نصب‌کننده AST اسکریپت `adr.ps1` را می‌خواند، پارامترها و dispatch را به‌صورت محافظه‌کارانه اضافه می‌کند، قبل از تغییر نسخهٔ پشتیبان `adr.ps1.bak` می‌سازد و روی نسخهٔ پشتیبان موجود نمی‌نویسد. اجرای دوباره نصب‌کننده بی‌اثر است. تغییرات را بازبینی کنید؛ پس از اطمینان می‌توانید backup را حذف کنید و آن را commit نکنید. برای اجرای مستقل، بدون نصب: `./export-adr.ps1 -Path docs/decisions -OutPath ./artifacts/decisions.html`. مسیر خروجی پیش‌فرض `docs/decisions/site/index.html` است.

## قابلیت‌ها و حدود

جست‌وجوی متن و فیلتر وضعیت با هم ترکیب می‌شوند؛ لینک ADRها، شمارنده‌ها، فهرست کناری، پشتیبانی RTL/LTR، صفحه‌بندی چاپ و حالت موبایل فراهم است. هنگام چاپ/PDF همهٔ ADRها چاپ می‌شوند، حتی اگر فیلتر فعال باشد. تولید PDF بومی نیست: دکمهٔ چاپ و گزینهٔ Save as PDF مرورگر را به‌کار ببرید.

فقط فایل‌های مستقیم پوشه با الگوی `NNNN-lower-kebab.md` خوانده می‌شوند. عنوان باید یک H1 مطابق شناسه، تاریخ ISO معتبر و یکی از وضعیت‌های `Proposed`, `Accepted`, `Rejected`, `Superseded` داشته باشد. پیکربندی برای CommonMark کامل نیست: پشتیبانی محدود از تیتر، پاراگراف، فهرست ساده، نقل‌قول، کد fence، inline code، bold/italic، لینک و چند خط پایه دارد؛ جدول‌ها و ساختارهای پیچیده Markdown محدودند. HTML خام به‌صورت متن امن نمایش داده می‌شود؛ schemeهای ناامن و رسانه‌های محلی حذف/متن ساده می‌شوند. لینک فایل ADR محلی به کارت شناسه نگاشت می‌شود. فونت از فونت‌های سیستمی استفاده می‌کند؛ فونتی بسته‌بندی نشده است. نمای Markdown `README` موجود عمداً دست‌نخورده می‌ماند.

## آزمون/بازبینی

```powershell
Invoke-Pester -Path ./tests/adr-export.tests.ps1 -Output Detailed
Invoke-Pester -Path ./tests -Output Detailed
git diff --check
```

مرحلهٔ فعلی خروجی HTML است؛ فایل‌های تولیدشده را فقط در صورت نیاز و طبق قرارداد مخزن stage کنید. بهتر است مقصدی مانند `artifacts/` انتخاب شود؛ افزودن آن به `.gitignore` فقط پس از بررسی قواعد مخزن. هیچ workflow یا فایل مخزن موجودی به‌طور خودکار عوض نمی‌شود. پیشنهاد پیام commit: `feat: add offline ADR HTML export`.
