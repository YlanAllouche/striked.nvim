---
title: "Rich Copy Fixture"
date: 2026-07-20
owner: "striked.nvim"
tags:
  - rich-copy
  - teams
  - markdown
detail:
  focus: true
  active: true
---

# Main Heading For Teams

This paragraph should keep its text while rich copy adds metadata table output for whole-buffer copies.

- [ ] Planned task [project:: rich-copy] [topic:: teams] [date:: 2026-07-20] [focus:: true] [active:: true]
- [x] Finished task [project:: rich-copy] [completion:: 2026-07-19] [focus:: false]
- [-] Cancelled task [project:: rich-copy] [completion:: 0%]
- [/] Work in progress [projects:: rich-copy, browser] [completion:: 45%] [active:: true]
- [l] Learned behavior [topic:: renderer] [date:: 2026-07-18]
- [R] Release candidate [project:: rich-copy] [completion:: 2026-07-21]
- [@] Bookmark entry [url:: https://example.com/rich-copy] [project:: docs] [topic:: demo] [date:: 2026-07-20]

## Secondary Heading

`Inline code` should remain intact.

```markdown
- [ ] Fenced task should not be transformed [date:: 2026-01-01]
- [@] Fenced bookmark should not be transformed [url:: https://hidden.example.com]
```

### Nested Heading

- Plain bullet that should remain a plain bullet.
