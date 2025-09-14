Based on the code diff and linked issues, generate a JSON object with a PR title and a technical PR description.

**Response Format Instructions:**

Your entire output must be a single, valid JSON object. Do not include any text, explanations, or markdown formatting outside of this JSON object.

The JSON object must have the following structure:
{
  "title": "string",
  "description": "string"
}

**Content Rules:**

1.  `title` (string):
    *   Follow the Conventional Commit Format: `type(scope): subject`.
    *   `type`: Must be one of `feat`, `fix`, `chore`, `refactor`, `style`, `ci`, `docs`.
    *   `scope` (optional): A noun for the codebase section (e.g., `api`, `camera`, `ui`, `auth`, `build`).
    *   `subject`: A short, imperative-mood summary of the change.
    *   Example: "feat(camera): Add continuous torch mode"

2.  `description` (string):
    *   This string must contain the full technical description formatted in Markdown.
    *   Do not add any introductory sentences. Start directly with the first relevant category heading.
    *   Group technical changes into the following categories using `###` (H3) headings. Only include categories with relevant changes.
        * `### ✨ New Functionality`
        * `### 🛠️ Refactoring & Architectural Changes`
        * `### 🐛 Bug Fixes`
        * `### ⚡ Performance Improvements`
        * `### 🧹 Maintenance & Chores`
    *   Under each category, list each major change using the following nested structure:
        *   Start with a primary bullet point (`*`). The line must begin with a **bolded, descriptive title** that summarizes the change, followed by a colon.
        *   Immediately after the colon, write a detailed paragraph explaining the change, its impact, and the technical reasoning.
        *   On a new line, add a nested and **bolded** bullet point that contains only the issue reference.
    *   **Example of the required format for a single item:**
        ```markdown
        *   **Sequential Image Processing:** The multi-shot camera has been re-architected to process images sequentially rather than in parallel. This significantly reduces memory pressure and resolves crashes that occurred when capturing a large number of photos (15+) in a single session.
            *   **Fixes #77**
        ```

---
GitHub Issues to close with this PR: