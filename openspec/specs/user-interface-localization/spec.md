# User Interface Localization Specification

## Purpose

Define Lunchpad's supported interface languages, runtime refresh behavior, string coverage, and the
boundary between Lunchpad-owned text and application bundle localization.

## Requirements

### Requirement: Supported interface languages

Lunchpad SHALL provide English and Simplified Chinese localizations and SHALL allow the user to
select Follow System, English, or Simplified Chinese independently of the current macOS language.

#### Scenario: Follow System resolves a Chinese preference

- **WHEN** Follow System is selected and the macOS preferred-language list contains a Chinese locale before a supported non-Chinese locale
- **THEN** Lunchpad resolves its interface language to Simplified Chinese

#### Scenario: Follow System finds no Chinese preference

- **WHEN** Follow System is selected and the macOS preferred-language list does not prefer a Chinese locale
- **THEN** Lunchpad resolves its interface language to English

#### Scenario: User selects an explicit language

- **WHEN** the user selects English or Simplified Chinese
- **THEN** Lunchpad uses that language regardless of the macOS preferred-language list

#### Scenario: Language choices are displayed in English

- **WHEN** Settings uses the English interface
- **THEN** the `zh-Hans` language choice is labeled `Chinese`

#### Scenario: Language choices are displayed in Chinese

- **WHEN** Settings uses the Simplified Chinese interface
- **THEN** the `zh-Hans` language choice is labeled `中文`

### Requirement: Complete Lunchpad-owned string coverage

Lunchpad SHALL localize all user-facing text it owns, including menus, Settings labels and choices,
launcher placeholders and empty states, protected system-folder names, accessibility descriptions,
and actionable validation or error messages.

#### Scenario: Interface is shown in English

- **WHEN** English is the resolved interface language
- **THEN** every Lunchpad-owned visible and accessibility string uses the English resource table

#### Scenario: Interface is shown in Simplified Chinese

- **WHEN** Simplified Chinese is the resolved interface language
- **THEN** every Lunchpad-owned visible and accessibility string uses the Simplified Chinese resource table

#### Scenario: Translation key is missing

- **WHEN** the selected language does not contain a requested key
- **THEN** Lunchpad falls back to the English value and does not display an empty label

### Requirement: Runtime language refresh

Changing the interface language SHALL update reusable interface objects during the current process
without requiring Lunchpad to restart.

#### Scenario: Language changes while Settings is visible

- **WHEN** the user selects another language in Settings
- **THEN** the Settings window, application menu, and status-item menu rebuild or refresh immediately in the selected language

#### Scenario: Language changes while the launcher exists

- **WHEN** the resolved interface language changes
- **THEN** launcher-owned strings and the protected Other folder name refresh while the current logical location remains valid

### Requirement: External application-name language boundary

The Lunchpad interface-language preference SHALL NOT override localization selection inside scanned
third-party application bundles.

#### Scenario: Explicit Lunchpad language differs from macOS

- **WHEN** the user selects a Lunchpad language different from the macOS preferred language
- **THEN** Lunchpad-owned strings use the selected language while discovered application names continue using macOS bundle-localization preferences
