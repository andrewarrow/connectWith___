# Product Requirements Document: 12x Family Event Scheduler

## Overview
12x is an iOS application designed to simplify family event planning by allowing households to schedule and coordinate 12 important events per year (one per month). Unlike traditional calendar apps that rely on internet connectivity and cloud services, 12x operates exclusively via Bluetooth, enabling family members living together to synchronize their schedules automatically whenever they come into proximity with one another. This offline-first approach ensures privacy, simplifies the user experience, and creates a more intimate way for families to plan and share their most important events.

## Core Features

### Bluetooth Sync Engine
- **What it does**: Continuously scans for other family members' devices running 12x and automatically syncs calendar data when in proximity.
- **Why it's important**: Eliminates the need for manual syncing, cloud services, or internet connectivity while ensuring all family members have the latest event information.
- **How it works**: Background Bluetooth scanning detects nearby devices running 12x. When devices are in range for a sufficient duration, they establish a connection and exchange encrypted calendar data, merging changes while preserving edit history.

### Monthly Event Cards
- **What it does**: Provides 12 visually distinct, color-coded cards (one per month) that display a single important event for each month.
- **Why it's important**: Creates a focused, uncluttered view of the family's most significant events, preventing calendar overload and emphasizing quality over quantity.
- **How it works**: Each card represents one month and displays key information: event title, location, and date. Cards are visually designed to resemble iOS Wallet passes with unique colors per month for easy recognition.

### Collaborative Editing
- **What it does**: Allows any family member to suggest, edit, or modify event details.
- **Why it's important**: Democratizes family planning and encourages participation from all household members.
- **How it works**: Any device can modify event details, with changes tracked in a version history. When devices sync, the system intelligently merges changes while preserving all family members' input.

### Change History Log
- **What it does**: Maintains a complete audit trail of all edits and suggestions made to event cards.
- **Why it's important**: Prevents data loss during sync conflicts and allows family members to see how plans evolved over time.
- **How it works**: Each edit is stored locally with timestamp and device identifier. During sync, the complete edit history is preserved and merged chronologically, with conflict resolution that prioritizes preserving all data.

### Family Device Management
- **What it does**: Allows users to discover, name, and manage family members' devices for syncing.
- **Why it's important**: Creates a personalized experience where devices are identified by family member names rather than technical identifiers.
- **How it works**: During initial setup and ongoing use, the app discovers nearby Bluetooth devices running 12x, allows users to name them (e.g., "Mom's iPhone" becomes "Mom"), and stores these associations in a local database.

### Debug and Diagnostics View
- **What it does**: Provides technical users with detailed insights into Bluetooth connectivity, sync status, and data exchange processes.
- **Why it's important**: Enables troubleshooting of connectivity issues and offers transparency into the app's operation.
- **How it works**: A hidden or developer menu provides real-time logs of Bluetooth discovery, connection attempts, data transfer statistics, and sync conflict resolutions.

## User Experience

### User Personas

**Family Coordinator (Primary)**
- 35-50 years old
- Typically organizes family activities
- Values simplicity and clarity
- Wants to reduce digital friction in family planning

**Family Member (Secondary)**
- Any age from teens to seniors
- Participates in family events but may not lead planning
- Wants to contribute ideas with minimal technical complexity
- Appreciates visual reminders of upcoming events

**Household Tech Support (Tertiary)**
- Family member who helps others with technology
- First point of contact for troubleshooting
- Appreciates technical details and diagnostic information
- Helps establish and maintain device connections

### Key User Flows

**Onboarding Flow**
1. App installation and launch
2. Welcome screens explaining the 12x concept
3. Permission request for Bluetooth access
4. Discovery wizard begins scanning for other family devices
5. When found, user names the discovered device(s)
6. Initial calendar view displayed with empty month cards

**Event Creation Flow**
1. User taps on a month card
2. Edit interface appears showing title, location, and date fields
3. User enters or modifies information
4. Preview shows how the card will look with changes
5. User confirms changes
6. Card updates with new information and edit is logged

**Bluetooth Sync Flow** (Passive)
1. Devices operate in background, scanning intermittently
2. When family members come into proximity, devices detect each other
3. Connection established automatically
4. Data synchronized with conflict resolution if needed
5. Brief notification indicates successful sync
6. Updated information appears in calendar view

**History Review Flow**
1. User taps on history/log icon
2. Complete chronological list of edits appears, grouped by month
3. User can expand entries to see details of changes
4. Filter options allow viewing changes by family member or time period

### UI/UX Considerations

- **Visual Language**: Clean, minimal interface inspired by iOS Wallet app, with focus on the 12 colorful month cards
- **Information Hierarchy**: Each card prominently displays month name, event title, and date with location in smaller text
- **Accessibility**: High-contrast colors, support for Dynamic Type, VoiceOver compatibility
- **Notifications**: Subtle, non-intrusive alerts for successful syncs and when family members suggest new events
- **Offline-First**: All functionality works without internet connection
- **Battery Consideration**: Bluetooth scanning optimized to minimize battery impact

## Technical Architecture

### System Components

#### Core Data Layer
- **Local Database**: SQLite database storing all event data, edit history, and device information
- **Data Models**: Event, EditHistory, FamilyDevice, SyncLog entities
- **Data Access Layer**: CRUD operations interface for all app components

#### Bluetooth Communication Stack
- **Background Scanner**: Low-power BLE scanner that runs periodically to discover nearby devices
- **Connection Manager**: Handles establishing and maintaining Bluetooth connections
- **Data Exchange Protocol**: Custom protocol for efficient transfer of calendar data
- **Conflict Resolution Engine**: Algorithms to merge conflicting edits while preserving information

#### User Interface Components
- **Card View Controller**: Manages the display and interaction with monthly event cards
- **Edit Interface**: Modal views for creating and editing event details
- **Onboarding Wizard**: Step-by-step introduction and device discovery process
- **History Logger**: UI for displaying the chronological edit history
- **Debug Console**: Technical interface showing Bluetooth operations

### Data Models

#### Event
```
id: UUID
month: Int (1-12)
title: String
location: String
day: Int (1-31)
createdAt: Date
lastModifiedAt: Date
lastModifiedBy: UUID (device identifier)
color: String (hex code)
```

#### EditHistory
```
id: UUID
eventId: UUID (reference to Event)
deviceId: UUID
deviceName: String
previousTitle: String?
newTitle: String?
previousLocation: String?
newLocation: String?
previousDay: Int?
newDay: Int?
timestamp: Date
```

#### FamilyDevice
```
id: UUID
bluetoothIdentifier: String
customName: String
lastSyncTimestamp: Date?
isLocalDevice: Bool
```

#### SyncLog
```
id: UUID
timestamp: Date
deviceId: UUID
deviceName: String
eventsReceived: Int
eventsSent: Int
conflicts: Int
resolutionMethod: String
details: String
```

### APIs and Integrations

#### Native iOS APIs
- **Core Bluetooth**: For device discovery and data exchange
- **Core Data**: For persistent storage of events and history
- **UserNotifications**: For sync notifications
- **BackgroundTasks**: For managing background Bluetooth operations

#### Custom Protocols
- **12x Sync Protocol**: Defines the data exchange format and procedures
- **Conflict Resolution Protocol**: Rules for merging conflicting edits

### Infrastructure Requirements

#### Device Requirements
- **iOS Version**: 14.0 or later
- **Bluetooth**: Bluetooth 4.2 or later
- **Storage**: Minimal (< 50MB for app and data)
- **Background Modes**: Bluetooth, Fetch

#### Security Considerations
- **Data Encryption**: All stored data encrypted using iOS data protection
- **Bluetooth Security**: Secure connection establishment with validation
- **Privacy**: No data transmitted outside of direct device-to-device connections

## Development Roadmap

### Phase 1: MVP Foundation
- Basic app shell with monthly card UI
- Local database for storing single device events
- Event creation and editing interface
- Simple onboarding flow (without Bluetooth discovery)
- Basic event card display and interaction

### Phase 2: Bluetooth Discovery
- Background Bluetooth scanning implementation
- Device discovery functionality
- Device naming and management interface
- Basic debug view for Bluetooth operations

### Phase 3: Data Synchronization
- Bluetooth connection establishment between devices
- Basic data exchange protocol implementation
- Initial sync functionality (without conflict resolution)
- Sync notification system

### Phase 4: Collaborative Features
- Edit history tracking implementation
- Conflict resolution algorithms
- Merged history view
- Enhanced sync log with detailed information

### Phase 5: Refinement
- Performance optimization for battery usage
- Enhanced UI animations and transitions
- Advanced debug console with detailed Bluetooth diagnostics
- User experience improvements based on testing

### Phase 6: Polish and Finalization
- Final visual design implementation
- Accessibility enhancements
- Comprehensive testing across different device models
- Error handling and edge case management

## Logical Dependency Chain

### Foundation Layer (First Priority)
1. **Local Database Implementation**: Create the core data storage system first as all other features depend on it
2. **Basic UI Framework**: Implement the card-based interface to provide a visual foundation
3. **Single-Device Event Management**: Build the event creation, editing, and display functionality

### Connection Layer (Second Priority)
4. **Bluetooth Discovery Engine**: Implement the background scanning and device discovery features
5. **Device Management**: Create the interface for naming and managing detected family devices
6. **Basic Debug View**: Develop initial diagnostic tools to validate Bluetooth functionality

### Synchronization Layer (Third Priority)
7. **Connection Establishment**: Build the system for creating stable Bluetooth connections between devices
8. **Data Exchange Protocol**: Implement the mechanism for transferring event data between devices
9. **Basic Synchronization**: Create the first version of the sync system (without conflict handling)

### Collaboration Layer (Fourth Priority)
10. **Edit History System**: Implement tracking of all changes to enable collaboration
11. **Conflict Resolution**: Develop algorithms for merging conflicting edits from different devices
12. **History Visualization**: Create the UI for viewing the edit history

### Optimization Layer (Final Priority)
13. **Battery Usage Optimization**: Refine the Bluetooth scanning to minimize power consumption
14. **Advanced Diagnostics**: Enhance the debug view with comprehensive connectivity information
15. **Edge Case Handling**: Implement robust error handling and recovery mechanisms

## Risks and Mitigations

### Technical Challenges

**Risk**: Bluetooth connectivity issues in various environments
- **Mitigation**: Implement robust retry logic, connection quality monitoring, and fallback mechanisms
- **Mitigation**: Create extensive logging to diagnose connection issues
- **Mitigation**: Test in various physical environments with different levels of interference

**Risk**: Battery drain from continuous Bluetooth scanning
- **Mitigation**: Implement intelligent scanning intervals based on time of day and usage patterns
- **Mitigation**: Use low-power scanning modes and optimize connection establishment
- **Mitigation**: Provide battery usage statistics and user controls for scanning frequency

**Risk**: Data conflicts during synchronization
- **Mitigation**: Design conflict resolution algorithms that preserve all edits in history
- **Mitigation**: Implement clear visualization of merged changes
- **Mitigation**: Create a manual conflict resolution interface for complex cases

### MVP Scope Management

**Risk**: Feature creep extending development timeline
- **Mitigation**: Strictly define MVP as single-device functionality with basic Bluetooth discovery
- **Mitigation**: Implement core functionality first, then layer in sync capabilities
- **Mitigation**: Use feature flagging to enable incremental testing of new capabilities

**Risk**: Overly complex initial implementation
- **Mitigation**: Start with simplified UI that can be enhanced later
- **Mitigation**: Focus on data integrity and core synchronization before adding advanced features
- **Mitigation**: Regular usability testing with target users to ensure simplicity is maintained

### Resource Constraints

**Risk**: Bluetooth testing requiring multiple physical devices
- **Mitigation**: Create a simulator mode for development that mimics Bluetooth behavior
- **Mitigation**: Establish a minimum test device set representing various iOS versions
- **Mitigation**: Develop automated testing for synchronization logic

**Risk**: iOS Bluetooth background mode limitations
- **Mitigation**: Research and implement best practices for background Bluetooth operation
- **Mitigation**: Design the system to work with intermittent connectivity
- **Mitigation**: Provide clear user education about iOS settings for optimal performance

## Appendix

### Research Findings

#### Bluetooth Range and Reliability
- Effective range for reliable data transfer: 10-30 feet depending on environment
- Connection establishment time: 1-5 seconds in optimal conditions
- Data transfer rate: Sufficient for calendar data (typically 5-20KB per full sync)
- Background scanning impact on battery: 3-8% additional battery usage per day with optimized settings

#### User Testing Insights
- Families prioritize simplicity over feature richness
- Visual design significantly impacts perceived ease of use
- Month-by-month planning aligns with how many families naturally think about events
- Device naming is critical for creating a personal feel

### Technical Specifications

#### Bluetooth Protocol Details
- Discovery: Uses BLE (Bluetooth Low Energy) advertisement with custom service UUID
- Connection: Standard GATT profile with custom service and characteristic UUIDs
- Data Exchange: JSON-based protocol with incremental syncing capability
- Security: Bluetooth encryption plus application-layer verification

#### Synchronization Algorithm
- Three-way merge for handling concurrent edits
- Timestamp-based conflict detection
- Edit preservation policy: Never delete information during conflict resolution
- Sync frequency: Automatic when devices in range, minimum 5-minute interval between syncs

#### Battery Optimization Strategy
- Adaptive scanning intervals based on:
  - Time of day (reduced scanning during typical sleep hours)
  - Recent successful connections (more frequent scanning if family members recently detected)
  - Motion detection (increased scanning when device is moving)
  - Battery level (reduced scanning at low battery levels)
