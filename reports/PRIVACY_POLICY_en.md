# Privacy Policy

**Last Updated**: February 14, 2026

## 1. Introduction

Thank you for using Thai Memo (the "App"). This App is designed to support Thai language learning. We respect your privacy and are committed to protecting your personal information with the utmost care.

This Privacy Policy explains what information the App collects, how it is used, stored, and shared. By using this App, you agree to this Privacy Policy.

## 2. Information We Collect

### 2.1 Automatically Collected Information

#### a) Authentication Information
- **Firebase Anonymous User ID (UID)**
  - Purpose: To provide basic App functionality
  - Collection Method: Anonymous authentication via Firebase Authentication
  - Link Status: Linked to user
  - Retention Period: Until app uninstallation

#### b) Device Information
- Device model
- Operating system version
- App version
- Purpose: To ensure App functionality and diagnose errors

### 2.2 User-Provided Information

#### a) Learning Content
The App collects the following user content:

- **Generated Sentences and Words**
  - Thai example sentences (AI-generated)
  - Japanese translations
  - Pronunciation guides
  - Word explanations

This information is **stored only on your local device** and is not sent to external servers.

#### b) Usage Data
- Sentence generation timestamps
- Favorite registrations
- Learning history

All of this data is **stored locally on your device** and is not synced to the cloud.

### 2.3 Information We Do NOT Collect

The App does **NOT collect** the following information:

- Personal identifiers such as name, email address, or phone number
- Location information
- Contacts
- Photos or videos
- Health information
- Financial information
- Browsing or search history
- Advertising identifiers (IDFA)

## 3. How We Use Information

Collected information is used solely for the following purposes:

### 3.1 Providing Core App Functionality
- Automatic generation of Thai example sentences (using Google Gemini AI)
- Storing and displaying generated sentences
- Managing learning history
- Favorite functionality

### 3.2 Notification Features
- Notifications when new sentences are generated
- Learning reminders (if enabled by user)

### 3.3 App Improvement
- Diagnosing errors and crashes
- Performance optimization

## 4. Data Storage Locations

### 4.1 Local Storage
The following data is stored only on your device:

- Generated sentences and words
- Learning history
- Favorite registrations
- App settings

**Storage Methods**:
- SQLite database (encrypted)
- Flutter Secure Storage (for important configuration data)

### 4.2 Cloud Services

#### Firebase (Google)
- **Stored Content**: Anonymous User ID (UID) only
- **Purpose**: Authentication management
- **Data Center**: Google Cloud Platform (asia-northeast1 region - Tokyo)
- **Retention Period**: Until account deletion

#### Google Gemini AI
- **Sent Content**: Sentence generation requests (situation information only)
- **Personal Information**: None included
- **Processing**: Immediately deleted after request processing
- **Retention Period**: Temporary (during processing only)

**Important**: The App does not send your personal information or learning content to Google Gemini AI. Only situation categories such as "greetings" or "food" are transmitted.

## 5. Data Sharing

### 5.1 Third-Party Sharing

The App does not share user information with third parties, except in the following limited cases:

#### a) Google (Firebase / Gemini AI)
- **Purpose**: To provide core App functionality
- **Shared Content**:
  - Firebase: Anonymous User ID (UID)
  - Gemini AI: Situation information for sentence generation
- **Privacy Policy**: [Google Privacy Policy](https://policies.google.com/privacy)

#### b) Legal Requirements
Information may be disclosed only in the following cases:
- When required by law, regulation, or legal process
- To protect public safety, defense, or security
- To protect the rights, property, or safety of third parties

### 5.2 Third Parties We Do NOT Share With

The App does **NOT share** information with:
- Advertising networks (no ads displayed)
- Data brokers
- Analytics services (other than Firebase)
- Social media platforms
- Marketing companies

## 6. Data Security

### 6.1 Security Measures

We implement the following security measures to protect your data:

#### Local Device
- **Encrypted Storage**: Flutter Secure Storage (iOS: Keychain, Android: EncryptedSharedPreferences)
- **Database Encryption**: SQLite database encryption
- **Access Control**: Accessible only within the App

#### Communications
- **HTTPS/TLS**: All network communications are encrypted with HTTPS (TLS 1.2 or higher)
- **Certificate Validation**: SSL certificate verification is performed

#### Firebase
- **Anonymous Authentication**: Uses anonymous authentication only, no personal information required
- **Data Isolation**: Data is isolated per user

### 6.2 Security Breach Response

In the event of a security breach:
1. Immediate investigation initiated
2. Notification to affected users
3. Implementation of preventive measures
4. Reporting to relevant authorities (if required)

## 7. User Rights

### 7.1 Right to Access Data

Users can access the following information within the App at any time:
- Saved sentences and learning history
- App settings

### 7.2 Right to Delete Data

Users can delete data using the following methods:

#### a) In-App Deletion
- **Individual Deletion**: Delete button for each sentence
- **Bulk Deletion**: "Delete All Data" in settings screen

#### b) App Uninstallation
- Uninstalling the App deletes all local device data
- Anonymous User ID on Firebase is automatically deleted after 180 days of inactivity

### 7.3 Notification Opt-Out

Users can disable notifications at any time:

#### iOS
1. Settings App → Thai Memo → Notifications
2. Turn off "Allow Notifications"

#### Android
1. Settings → Apps → Thai Memo → Notifications
2. Turn off all categories

#### In-App Settings
- Turn off "Enable Notifications" in Thai Memo settings screen

### 7.4 Data Portability

All App data is stored on your local device, so you can export data at any time using:
- Database file backup (developer feature)
- Export functionality (planned for future versions)

## 8. Children's Privacy

### 8.1 Age Restrictions

This App is intended for users **aged 13 and above**.

The App does not knowingly collect personal information from children under 13. If you are a parent or guardian and believe your child under 13 is using the App, please contact us using the information below.

### 8.2 Parental Consent

If a child under 13 uses this App, consent from a parent or legal guardian is required.

### 8.3 COPPA / GDPR-K Compliance

The App complies with the following children's online privacy protection laws:
- **COPPA (US)**: Protection of personal information of children under 13
- **GDPR (EU)**: Consent requirements for children under 16 (13-16 depending on country)

Since the App uses only anonymous authentication and does not collect children's personal information, it does not violate these laws.

## 9. International Data Transfers

### 9.1 Data Processing Regions

- **Primary Data**: On user's device (no international transfer)
- **Firebase**: Google Cloud Platform - asia-northeast1 (Tokyo)
- **Gemini AI**: Google data centers (global)

### 9.2 General Data Protection Regulation (GDPR)

For users in the European Economic Area (EEA), we guarantee the following rights:

#### Rights Under GDPR
- **Right to Access**: Access to stored data
- **Right to Rectification**: Correction of inaccurate data
- **Right to Erasure (Right to be Forgotten)**: Request data deletion
- **Right to Restriction**: Request restriction of data processing
- **Right to Data Portability**: Request data transfer
- **Right to Object**: Object to data processing

#### Legal Basis for Data Processing
- **Performance of Contract**: Provision of App services
- **Legitimate Interests**: App improvement, security

### 9.3 California Consumer Privacy Act (CCPA)

California residents have the following rights:
- **Right to Know**: Request disclosure of collected personal information
- **Right to Delete**: Request deletion of personal information
- **Right to Opt-Out of Sale**: Refuse sale of personal information (we do not sell)
- **Right to Non-Discrimination**: No adverse treatment for exercising CCPA rights

**Important**: The App does not sell or share your personal information.

## 10. Cookies and Tracking

### 10.1 Cookie Usage

The App does **NOT use web cookies**.

### 10.2 Tracking

The App does **NOT perform** any of the following tracking:
- Cross-app tracking
- Cross-site tracking
- Advertising tracking
- Behavioral targeting

### 10.3 App Tracking Transparency (ATT)

The App does not engage in activities that fall under Apple's definition of tracking, so it does not request ATT framework permissions.

## 11. Changes to Privacy Policy

### 11.1 Notification of Changes

If we change this Privacy Policy, we will notify you through:
1. Updating the "Last Updated" date at the top of this page
2. In-app notifications (for significant changes)
3. Change log during app updates

### 11.2 Acceptance of Changes

If significant changes are made, users can choose to:
- Accept the changes and continue using the App
- Decline the changes, stop using the App, and delete data

### 11.3 Archive of Changes

Past Privacy Policies can be viewed in the following GitHub repository (in preparation):
- [Privacy Policy Archive] (link in preparation)

## 12. Contact Us

If you have questions, concerns, or data deletion requests regarding privacy, please contact us:

**Developer**: Thai Memo Development Team

**Email**: privacy@thaimemo.app (in preparation)

**Business Hours**: Weekdays 10:00-18:00 (Japan Standard Time)

**Response Time**: Within 7 business days

### Data Deletion Requests

If you wish to delete your data, please contact us with the following information:
- Device information used (iOS/Android, version)
- App version
- Scope of data to be deleted

## 13. App Store Privacy Disclosure

Content disclosed in App Store Connect:

### Collected Data
| Data Type | Purpose | Link Status |
|-----------|---------|-------------|
| User ID (Firebase UID) | App Functionality | Linked to User |
| Product Interaction | App Functionality | Linked to User |
| Crash Data | App Functionality, Analytics | Linked to User |

### Tracking
- **Tracking**: None

### Third-Party SDKs
- Firebase Authentication
- Firebase Cloud Functions
- Google Generative AI (Gemini)

---

## 14. Consent

By downloading, installing, and using this App, you agree to this Privacy Policy.

If you do not agree to this Privacy Policy, please refrain from using this App.

---

**This Privacy Policy was last updated on February 14, 2026.**

© 2026 Thai Memo Development Team. All rights reserved.
