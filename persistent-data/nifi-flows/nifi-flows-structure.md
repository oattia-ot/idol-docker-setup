# NiFi Flows Structure & Categorization

## Current Folder Structure

```
nifi-flows/
├── customize/
│   └── 01-grok-summary.json
├── demos/
│   ├── 01-basic-demo.json
│   ├── 02-general-demo.json
│   └── 03-metadata-enrichment-demo.json
├── features/
│   ├── 01-extract-pdfs-from-web.json
│   └── 02-audit-trail-for-searches.json
├── tutorials/
│   └── 01-extract-opentext-content-management.json
├── utilities/
│   └── 01-execute-stream.json
└── nifi-flows-structure.md
```

---

## Folder Purpose

| Folder        | Purpose                                              |
|---------------|------------------------------------------------------|
| `demos/`      | General learning & showcase flows                    |
| `features/`   | Specific capability / use-case flows                 |
| `utilities/`  | Technical / reusable helper flows                    |
| `tutorials/`  | Step-by-step guided flows                            |
| `customize/`  | User imported / custom NiFi flows                    |

---

## File Inventory

| File                                                         | Category   | Description                                          |
|--------------------------------------------------------------|------------|------------------------------------------------------|
| `demos/01-basic-demo.json`                                   | demos      | Entry-level / introductory flow                      |
| `demos/02-general-demo.json`                                 | demos      | Broader showcase of common patterns                  |
| `demos/03-metadata-enrichment-demo.json`                     | demos      | Feature demo focused on enrichment                   |
| `features/01-extract-pdfs-from-web.json`                     | features   | Specific extraction use-case                         |
| `features/02-audit-trail-for-searches.json`                  | features   | Auditing / compliance capability                     |
| `utilities/01-execute-stream.json`                           | utilities  | Technical / processor-level utility                  |
| `tutorials/01-extract-opentext-content-management.json`      | tutorials  | Extract content from OpenText Content Management     |
| `customize/01-grok-summary.json`                             | customize  | User imported / custom flow                          |
