# ADR Lab (Architecture Decision Records Toolkit)

A lightweight PowerShell 7+ toolkit for managing Architecture Decision Records (ADR) with automated validation and Git integration.

---

## Features

- Automatic Numbering & Naming: Sequential 4-digit numbers with kebab-case ASCII names.
- Lifecycle Management: Proposed, Accepted, Rejected, and Superseded states with bi-directional links.
- Integrity Validation: -VerifyLinks and -VerifyIndex switches for CI/CD and pre-commit checks.
- Native Git Hooks: Pre-commit and pre-push hooks without external dependencies.
- HTML Export: Interactive standalone dashboard generation via export-adr.ps1.

---

## Prerequisites

- PowerShell 7.4+
- Git 2.30+
- Pester 5.5.0+

---

## Quick Start

### 1. Setup Local Git Hooks

./setup-hooks.ps1

### 2. Create an ADR

./adr.ps1 -Title 'Use SQLite for Local Storage'

### 3. Change Status

./adr.ps1 -Status Accepted -Number 1

### 4. Supersede an ADR

./adr.ps1 -Title 'Migrate to SQL Server' -Supersedes 1

### 5. Validate Repository

./adr.ps1 -VerifyLinks
./adr.ps1 -VerifyIndex

### 6. Export HTML Dashboard

./export-adr.ps1 -Path docs/decisions -OutputPath docs/decisions/index.html

### 7. Run Tests

Invoke-Pester -Path ./tests -Output Minimal

---

## License

MIT
