# Localization resources

Shipping catalogs contain reviewed units only. Missing entries fall back to the source language. `Review/` holds machine-generated drafts and is not included in applications.

The 13-language localization is **not complete**. Do not market this release as fully localized. Current reviewed units: {"ru": 446, "en": 17, "zh-Hans": 14, "es": 14, "hi": 9, "ar": 9, "pt-BR": 14, "fr": 14, "de": 14, "ja": 14, "ko": 9, "it": 14, "tr": 14}; total keys: 448.

Dynamic presentation strings use Shared/Localization.swift; identifiers, user input and persisted data are not translated. The full release audit is scripts/localization/audit_catalogs.py in the Connector repository. It must pass before declaring full localization.
