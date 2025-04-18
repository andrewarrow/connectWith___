# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands
- Build app: `xcodebuild -scheme connectWith___ -destination "platform=iOS Simulator,name=iPhone 15" build`
- Run app: `xcodebuild -scheme connectWith___ -destination "platform=iOS Simulator,name=iPhone 15" build run`
- Clean build: `xcodebuild clean`

## Code Style Guidelines
- Imports: Group Apple frameworks first, then third-party libraries
- Formatting: 4-space indentation, no trailing whitespace
- Types: Use Swift strong typing with proper optionals
- Naming: 
  - Classes/structs/enums: UpperCamelCase
  - Variables/functions: lowerCamelCase
  - Use descriptive names that reflect purpose
- SwiftUI Views: Keep under 100 lines by extracting subviews
- Error Handling: Use do/catch for explicit error handling, avoid forced unwrapping
- MARK comments for logical sectioning of code
- Use extensions to organize protocol conformance
- For CoreData entities, use extensions for property access
- Prefer composition over inheritance