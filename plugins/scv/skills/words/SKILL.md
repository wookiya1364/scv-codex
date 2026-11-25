---
name: words
description: "Show or change the project's word dictionary: the words you do not want to read and the word to say instead, inflections included (scv/words/). Use when the user wants B said instead of A, asks which words are replaced, or invokes $scv:words."
---

# SCV Words

1. Read `../../references/codex-runtime.md` completely and apply it.
2. Read `../../vendor/scv-core/core/protocols/words.md` completely.
3. Run the words protocol with the safely parsed arguments: nothing or `list`, `add <word to avoid> <word to use>`,
   `remove <word to avoid>`, `fill`, or a plain request such as "say B instead of A".
4. After a change, relay what is now replaced by what and that it holds from the next turn on. When an entry has no
   forms, say it catches only the word itself and offer to fill them.
5. Never edit `scv/words/WORDS.tsv` by hand, and never add, change or remove a word the user did not ask for.
