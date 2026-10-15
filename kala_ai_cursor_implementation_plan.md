# Kala AI --- Cursor Implementation Plan

**Purpose:** Evolve the existing Flutter app into a guided AI creative
studio with stronger repeat usage, while preserving the current app
architecture, editor flows, credit economy, and visual identity.

**Audience:** Cursor / coding agent working inside the existing Kala AI
repository\
**Implementation approach:** Inspect first, implement incrementally,
reuse existing systems, and avoid backend/API changes unless explicitly
required and supported.

------------------------------------------------------------------------

## 0. Non-negotiable constraints

1.  **Do not rebuild the app or replace its visual identity.** Preserve
    the existing dark theme, purple/cyan accents, rounded cards, bottom
    navigation, Editor, Store, Settings, and existing image/video tools.
2.  **Explore banner already exists.** It is a slideshow that randomly
    advertises five templates. Keep that behavior. Improve its
    content/quality only if needed; do not replace it with a new banner
    concept or add another carousel.
3.  **Do not implement preview-before-spend.** The current generation
    architecture does not support a genuine low-cost preview. Do not
    simulate one or imply the user can preview the actual output for
    free.
4.  **Do not implement video extension.**
5.  **Do not implement brush-to-edit, tap-to-edit, or mask painting UI
    in this project.** The current app uses Kie AI's Qwen Image 2.1
    endpoint. The underlying Qwen Image 2.1 model supports region
    selection and separate masks, but the currently documented Kie
    `qwen/image-edit` request schema exposes `prompt`, `image_url`, and
    generation parameters, with no documented mask input. Do not build a
    mask UI until the exact endpoint contract is verified and a working
    end-to-end request is demonstrated.
6.  **Do not add a second image/video job system.** Use the app's
    existing job submission, polling/callback, result storage, credit
    deduction/refund, and error handling flows.
7.  **Do not hardcode API keys or call Kie AI directly from Flutter.**
    Keep secrets and API calls in the existing backend/orchestrator.
8.  **Do not charge users for a failed generation.** Reuse existing
    credit handling. Audit it before adding new flows.
9.  **Do not assume features exist.** Inspect the repository and
    identify current equivalents before coding. Extend existing
    implementations rather than duplicating them.
10. **Avoid scope creep.** Implement in phases below. Do not attempt the
    entire roadmap in one large refactor.

### Qwen mask capability finding

-   Official Qwen Image 2.1 documentation describes local editing using
    circles, painted annotations, and a separate mask.
-   Kie AI's documented `qwen/image-edit` request example uses an input
    image URL and prompt; the published schema does not show a mask
    parameter.
-   Therefore, for the current Kie integration, treat mask editing as
    **unsupported/unverified at the provider API layer** and leave it
    out. Ordinary prompt-guided image editing and multiple-reference
    workflows can still be considered where the exact Kie endpoint
    supports them.
-   References:
    -   Qwen model documentation:
        https://github.com/QwenLM/Qwen-Image-2.1
    -   Kie edit endpoint: https://docs.kie.ai/market/qwen/image-edit
    -   Kie Qwen Image 2.1 page: https://kie.ai/qwen-image-2.1

------------------------------------------------------------------------

## 1. First task for Cursor: repository reconnaissance

Before editing files, inspect and report:

1.  Flutter version, package structure, routing/navigation approach,
    state management, theme/design tokens, and current bottom
    navigation.
2.  Existing Explore/AI Explore screen and its template/card model.
3.  How the current five-template random slideshow banner is populated
    and how random selection avoids duplicates (if it does).
4.  Existing `tool_config.json` or equivalent dynamic configuration,
    template definitions, prompt construction, and tool submission path.
5.  Existing image generation, image editing, image-to-video,
    text-to-video, upscale, background removal, and restoration flows.
6.  Existing job lifecycle: create job, show progress, poll/callback,
    download/save output, retry, cancellation, credit deduction/refund.
7.  Existing history/gallery/favorites/projects or local persistence.
    Reuse these if present.
8.  Existing image upload/reference picker and multi-image selection
    support.
9.  Existing analytics/event tracking, if any.
10. Relevant tests and build/lint commands.

**Deliverable before implementation:** a short repository map with the
actual file paths/classes that will be changed, the existing reusable
components, and any blockers. Do not guess file names. Then implement
Phase 1.

------------------------------------------------------------------------

## 2. Product direction

Kala AI should feel like a **creative studio that takes users from an
idea to a finished asset**, not just a gallery of AI models.

Core user journey:

1.  User opens Explore.
2.  User selects an outcome or a familiar tool.
3.  Kala asks only for the inputs necessary for that workflow.
4.  Kala preconfigures a suitable prompt/settings/model using the
    current configuration system.
5.  User sees the complete credit cost before submitting.
6.  Existing job system generates the result.
7.  Result screen offers relevant next actions, save/reuse options, and
    project history.
8.  User can return later and continue a project or repeat a successful
    workflow.

Keep the existing Editor for direct/manual control. Explore is the
guided discovery and outcome-oriented entry point.

------------------------------------------------------------------------

## 3. Explore screen redesign --- reuse the existing screen

### 3.1 Preserve current elements

-   Keep current app header and credit balance/top-up entry.
-   Keep current bottom navigation.
-   Keep the existing six Pro Tools shortcuts (Create Image, Edit Image,
    Create Video, Animate Image, Upscale Image, Remove Background),
    including the current "More" behavior.
-   Keep the existing featured banner slideshow of five randomly
    selected template advertisements.
-   Keep the existing template catalogue and its current visual card
    style, but improve information architecture and template metadata.
-   Keep the current dark/purple/cyan visual language and
    accessibility/spacing conventions.

Do not duplicate a tool in multiple prominent sections unless there is a
clear contextual reason.

### 3.2 New Explore information architecture

Recommended order:

1.  **Header** --- Kala AI, credit balance, existing saved-work/folder
    entry if it already exists.
2.  **Pro Tools** --- existing quick access grid. Preserve its current
    footprint or make it collapsible only if repository UX patterns
    already support this.
3.  **Featured template slideshow** --- existing random five-template
    banner; preserve it.
4.  **"What do you want to create?" outcome shortcuts** --- compact
    cards/chips for:
    -   Edit a photo
    -   Create an image
    -   Create a video
    -   Create social content
    -   Improve an old/low-quality photo These should route into
        existing tools/templates, not create parallel generation flows.
5.  **Personal entry point** --- adaptive section described in 3.3.
6.  **Category filters** --- retain All, Trending, Video, Photo; add
    Portrait, Creator, Business, Restore/Enhance only if there are
    enough templates to make each useful. Use horizontal scrolling and
    preserve selection while browsing.
7.  **Curated template sections/cards** --- "Popular this week",
    "Portraits", "Creator & business", "Photo restoration", "Styles &
    experiments", and "Video & animation". Hide empty categories.
8.  **Bottom navigation** --- unchanged.

If the screen becomes too long, keep the first screen focused: existing
tools, banner, one personal entry, then templates. Do not put every
category on the initial viewport.

### 3.3 Personal entry point: exact behavior

The personal section should be useful, not a decorative greeting.
Implement it as a state-aware section, with this priority:

**State A --- user has recent projects/generations** - Title: "Continue
creating" - Show up to two recent project/result cards. - Each card
shows a real thumbnail, a concise project/template name, and a relative
date only if that metadata is available. - Tap opens the result/project
detail or editor with the saved input/settings where supported. - Add
"See all" only if a full history/projects screen exists or is
implemented. - Never show placeholder thumbnails or fake history.

**State B --- no projects, but saved favorites/recipes exist** - Title:
"Your shortcuts" - Show up to two saved templates/recipes. - Tap opens
the same template with its saved settings. - If only favorites exist,
call the section "Your favorites", not "Continue creating".

**State C --- no history/favorites/recipes** - Show a compact starter
card: "Start your first creation" with 2--3 popular workflows, e.g. AI
Headshot, Glow Up Photo, Animate Portrait. - Do not show an empty
history section. - The card should deep-link to the existing workflow
configuration.

**Data and privacy** - Reuse existing local/backend history if
available. Do not introduce cloud account requirements solely for this
feature. - If persistence is currently local, use the existing
persistence strategy and do not upload private images just to power
Explore. - Show only successfully completed generations in "Continue
creating"; failed jobs can remain in the existing history/error UI if
present. - Add a clear path to delete a project/history item if the
underlying feature supports it. - Do not cache full-resolution images
unnecessarily. Reuse existing thumbnails or generate/store a small
thumbnail with the current image pipeline.

### 3.4 Template card requirements

Every template should have a consistent schema (extend current schema;
do not create a competing one):

-   Stable `id`
-   `title`
-   Short outcome-oriented `subtitle`
-   `category`
-   `badge` (optional: Trending, Popular, Professional, Anime, etc.)
-   `thumbnail`/preview asset
-   `inputType` or supported input requirements
-   `toolType`/destination matching an existing flow
-   `prompt` or prompt/config reference
-   optional safe default settings
-   expected credit cost if static; otherwise derive from the existing
    pricing system
-   optional tags for filtering/search
-   optional "featured"/"trending" metadata if the app already supports
    it

Requirements: - Do not put secrets, API configuration, or provider keys
in template data. - Do not store a stale hardcoded credit price when
cost can be derived from the current tool configuration. - Cards must
have real visual examples and appropriate aspect ratios. - Loading/error
states should not leave permanent spinners or broken cards. - Use stable
IDs, not list indices, for selection, favorites, and persistence. -
Ensure accessibility: readable contrast, tap targets, and labels that do
not truncate into ambiguity.

### 3.5 Template detail / launch flow

When a user taps a template:

1.  Open the existing template bottom sheet or detail page pattern if
    available.
2.  Show a real preview image, title, concise description, required
    input type, and exact cost or cost calculation.
3.  Explain what the workflow will do in one sentence.
4.  Provide a clear primary action ("Use template" / "Continue").
5.  Launch the existing tool with the prompt and safe settings
    prefilled.
6.  Keep the prompt editable where the existing tool supports it.
7.  Validate required inputs before enabling Generate.
8.  Show any extra cost for optional upscale/variations before
    generation.
9.  Do not run a model call until the user taps Generate.
10. Do not claim that a preview is a free model output. The banner/card
    preview is a sample/template advertisement only.

------------------------------------------------------------------------

## 4. Goal-based workflows

Add a curated set of outcome-based workflows using the existing
template/config mechanism. Do not create a separate hardcoded screen for
each template.

Initial workflows to include (reuse existing templates where possible):

### Portrait and personal photos

-   AI Headshot / Professional Profile
-   Glow Up Photo (lighting/skin improvement; avoid claiming guaranteed
    perfect skin)
-   Portrait Enhance
-   Outfit Change
-   Cinematic Portrait
-   Anime Portrait
-   Background Change
-   Photo Restore (old/blurry/compressed photo; be honest about
    limitations)
-   Face Restore, only if the current backend tool truly supports it

### Creator and social

-   YouTube Thumbnail
-   Reel/Short Cover
-   Instagram Post / Story
-   Channel/Profile Branding
-   Matching social post pack

### Small business

-   Product Photo
-   Product Background Cleanup
-   Product Listing Image
-   Sale/Promotion Banner
-   Catalogue Image Set

### Video and animation

-   Animate Portrait
-   Animate Image
-   Cinematic Video from text, if already supported
-   Image-to-video from an existing image
-   Slow Motion, only if the existing model/tool genuinely supports it

### Style and experimentation

-   3D Cartoon
-   Comic Book
-   Clay Render
-   Cyberpunk
-   Neon Glow
-   Cinematic
-   Anime/Illustration
-   Other existing styles

Do not add a template merely because its name sounds attractive. Confirm
it maps to an actual working workflow, model capability, prompt, and
output.

### Workflow config behavior

-   Store template prompt/config in the existing `tool_config.json` or
    the established source of truth.
-   Use the same job submission route as the corresponding tool.
-   Support a template identifier for analytics and history.
-   Prefill prompt/settings without locking users out of editing.
-   Keep default inputs minimal: only ask for image/video inputs that
    are required.
-   Where a template accepts multiple references, enforce the actual
    provider/model limit and display the purpose of each reference slot.
-   Keep the user's original image and prompt available for retries if
    existing job architecture allows it.

------------------------------------------------------------------------

## 5. Smart next actions after a successful generation

Implement this early because it increases utility without needing a new
model or separate backend workflow.

After a job succeeds, show a row or grid of contextually relevant
actions. Do not show the same generic actions for every result.

Examples:

**After an image edit** - Try another style - Make another variation -
Upscale image - Remove/change background (if supported) - Save as
recipe - Add to project

**After text-to-image** - Create variations - Try a different style -
Animate this image (only if the existing image-to-video flow accepts
it) - Use as a reference in Edit Image - Save as recipe/project

**After image-to-video** - Download/share - Create another version -
Reuse source image in another workflow - Add to project

**After upscale/restore** - Compare original/result - Download/share -
Save result - Reopen the source in the appropriate editor

Rules: - Only offer actions supported by the current app. - Pass the
actual output image/video as the next workflow input when supported; do
not ask the user to upload it again unnecessarily. - Make credit costs
visible before the next generation. - Do not auto-run the next action. -
Use existing credit and job flows. - Do not implement video extension.

------------------------------------------------------------------------

## 6. Projects, history, and version recovery

First inspect whether a usable history/gallery already exists. If it
does, extend it instead of adding another gallery.

### 6.1 Minimum viable project/history model

Store, where supported by existing architecture: - stable project/result
ID - creation timestamp - output media path/URL and thumbnail - media
type (image/video) - originating tool/template ID - original prompt and
final prompt if prompt enhancement changed it - source/reference image
references if safely available - non-secret settings used - job status -
credit amount charged - optional parent result ID for a derived
edit/variation - favorite flag or link to existing favorites

Do not store API keys, tokens, or sensitive server-only data in
client-side project records.

### 6.2 Behavior

-   A completed result can be opened, saved, downloaded/shared through
    existing platform behavior, or reused as an input.
-   Reopening a result should restore the prompt/settings when the
    existing tool supports it.
-   Each new edit/variation should create a new result/version, not
    overwrite the original.
-   Show a simple chronological history, grouped by day if convenient.
-   Support deleting an item and removing it from local/project
    persistence.
-   Handle deleted/expired remote URLs gracefully.
-   Avoid promising indefinite cloud storage unless the backend actually
    provides it.
-   Add a "Continue creating" entry point on Explore using the rules in
    Section 3.3.

If no backend project store exists, start with the repository's existing
local persistence mechanism. Keep the model abstract enough that cloud
sync could be added later, but do not build cloud sync in this phase.

------------------------------------------------------------------------

## 7. Saved recipes and favorites

A **recipe** is a reusable workflow setup; a **favorite** is a bookmark.
Do not treat them as the same object.

### Favorite

-   Save/unsave a template or style.
-   Make favorites accessible from Explore and the relevant
    editor/template browser.
-   Persist using the existing local/user persistence system.

### Recipe

Save: - recipe ID and name - originating tool/template ID -
prompt/configuration - selected style and supported settings - reference
asset IDs only if the app can safely retain them - created/updated
timestamps

Recipe behavior: - "Save recipe" is offered after a successful result or
from a template editor. - Allow rename/delete. - "Use recipe" opens the
original workflow with values prefilled. - Recalculate current credit
cost at use time; never assume the saved recipe's old cost is still
valid. - If a model or setting is no longer available, explain and fall
back only where safe. Never silently change the meaning of the recipe. -
Keep the first implementation simple: favorites first if no
history/persistence infrastructure exists, then recipes.

------------------------------------------------------------------------

## 8. My Characters and reference collections

Build this after projects/history because it relies on persistent media
and reference selection.

### 8.1 Purpose

Allow users to save a recurring person, pet, mascot or fictional
character and reuse its reference images in supported image
editing/generation and image-to-video workflows.

### 8.2 Character data

-   stable character ID
-   user-defined name
-   cover thumbnail
-   one or more reference image IDs/paths
-   optional description/notes written by user
-   creation/updated timestamps
-   privacy/deletion controls

### 8.3 UI

-   "My Characters" entry from Explore or the project/library area.
-   Empty state: explain what a character library does and offer "Create
    character" / "Add reference photos".
-   Character cards use real thumbnails and user names.
-   Character detail view shows references and actions: add/remove
    reference, rename, delete, use in a supported workflow.
-   When selecting a character in a workflow, show which reference
    image(s) will be sent.

### 8.4 Important model/provider rules

-   Do not promise exact face/identity preservation;
    reference-conditioned generation can vary.
-   Enforce the exact input count supported by the selected Kie
    endpoint. Qwen Image 2.1 as a model supports up to 10 reference
    images, but the app's particular Kie endpoint contract must be
    checked before exposing 10 slots.
-   Never silently attach a user's saved references to a request. The
    user must explicitly choose a character/reference for each job.
-   Use local persistence first if that matches the app's current data
    strategy. Do not upload private photos to a new cloud store without
    a clear user-facing reason and deletion behavior.
-   Support deletion of a character and its stored references according
    to the current storage architecture.

------------------------------------------------------------------------

## 9. Content packs and batch workflows

A content pack is a guided workflow that creates a coordinated set of
outputs from one brief/reference. Implement only after single-output
templates and history are reliable.

### 9.1 Initial pack types

-   Creator pack: thumbnail + square post + story/vertical cover.
-   Small-business pack: clean product image + promotional visual +
    catalogue/listing image.
-   Event pack: invitation/poster + social announcement + story.
-   Brand pack: multiple assets sharing colors/style and a reusable
    prompt/config.

### 9.2 User flow

1.  Select a pack.
2.  Enter a short brief and upload required source images.
3.  Choose outputs from the supported pack.
4.  Show the total estimated credit cost before submission.
5.  Let the user remove optional outputs.
6.  Submit each output through the existing job system.
7.  Show per-output status, failure, retry and resulting asset.
8.  Charge/refund according to existing credit rules and only for
    successfully completed billable outputs.
9.  Allow downloading/sharing outputs individually; provide bulk export
    only if it fits existing file handling.

### 9.3 Cost and reliability

-   Do not present a pack as one cheap generation if it launches
    multiple paid model calls.
-   Do not make all outputs mandatory.
-   Avoid submitting an unbounded batch.
-   Add queue/concurrency limits consistent with existing backend
    limits.
-   A failed output must not cause successful outputs to be lost.
-   Make retries idempotent so a retry does not accidentally
    double-charge.

------------------------------------------------------------------------

## 10. Creator and business studios

Implement as curated templates/content packs first, not separate complex
editors.

### Creator studio

-   YouTube thumbnail
-   Short/Reel cover
-   Social post/Story
-   Channel/profile branding
-   Matching multi-format content pack

### Business studio

-   Product photo on a clean background
-   Product lifestyle scene
-   Catalogue/listing image
-   Promotional/sale creative
-   Consistent set of images for several products

Rules: - Use platform aspect-ratio presets, but keep the generated
output's actual dimensions visible/known. - Do not claim text will
always render perfectly. If text-heavy assets are unreliable with the
current model, use an existing text/layout editor or make the template
explicitly image-first. - Never invent a brand logo or claim a user's
product label is preserved perfectly. - Make it easy to reuse a previous
product/reference image. - Keep the base model cost and any optional
upscale costs visible. - Prefer templates and prompt/configuration
improvements over adding new provider integrations at this stage.

------------------------------------------------------------------------

## 11. Export presets and platform-ready outputs

Implement a small preset selector using the existing output and
crop/resize utilities where possible.

Initial presets: - Square post (1:1) - Portrait post (4:5) -
Story/Reel/Short (9:16) - YouTube thumbnail (16:9) - Profile photo
(1:1) - Product listing (use a configurable square/portrait option)

Requirements: - Explain whether the preset changes generation aspect
ratio, crops the result, or resizes after generation. - Do not claim a
resize creates new detail. - Preserve the original generated result. -
Offer "Save copy" rather than destructively overwriting. - Use platform
names only as destination labels; avoid implying official affiliation. -
Do not add arbitrary resolution choices that the provider does not
support.

------------------------------------------------------------------------

## 12. Explore search, categories, and discovery

Add search only if the template library has enough items for search to
help.

-   Search by title, outcome, style, tags and category.
-   Support empty state ("No matching templates") with a clear reset
    action.
-   Keep category filters horizontally scrollable and
    keyboard-accessible.
-   Retain the selected filter when returning from a template if
    navigation architecture supports it.
-   "Trending" should be based on real app activity if analytics are
    available. If not, use an explicitly curated "Popular" collection
    rather than pretending it is live trending data.
-   Use stable ordering and stable IDs. Randomize only the existing
    featured banner's five ads, not the entire catalogue on every
    rebuild.
-   Avoid showing duplicate cards in multiple adjacent sections unless
    intentionally curated.
-   Do not create fake engagement counters or fabricated popularity
    metrics.

------------------------------------------------------------------------

## 13. Prompt enhancement and workflow quality

-   Reuse the current prompt-enhancement toggle/service.
-   Preserve the user's original prompt and, where useful, show the
    enhanced prompt as editable text.
-   For templates, prompt enhancement should not remove required
    instructions such as preserving the person, product, composition, or
    unchanged background.
-   Do not run a separate enhancement API call unless the existing
    architecture supports it and its cost is accounted for.
-   Keep prompts in the current source of truth (`tool_config.json` or
    existing template config).
-   Add test cases for representative prompts and required preservation
    constraints.
-   If prompt enhancement fails, let the user proceed with the original
    prompt rather than blocking generation.

------------------------------------------------------------------------

## 14. Credit transparency and error handling

Every generation entry point must use the same source of truth for
credit cost.

Before submission: - Show base cost. - Show optional upscale/variation
cost. - Show total cost. - Disable Generate if the user cannot afford
it, with a route to Store/top-up. - Avoid conflicting costs between
Explore cards, template details, editor settings and the Generate
button.

During/after submission: - Prevent duplicate taps from creating
duplicate jobs. - Show job progress using the existing job system. -
Handle timeout, failure, missing output URL and expired URL states. -
Refund failed billable jobs according to existing policy. - Make retries
explicit and safe. - Log provider errors in backend diagnostics without
exposing secrets or raw internal errors to users.

Do not introduce a new credit system. Audit the existing implementation
and fix inconsistencies first.

------------------------------------------------------------------------

## 15. Analytics to validate retention

Reuse existing analytics if present. Do not add invasive tracking or log
raw prompts/private images.

Suggested events: - `explore_opened` - `template_viewed` (template ID,
category) - `template_started` - `generation_submitted` (tool/template
ID, model family, credit cost) - `generation_succeeded` -
`generation_failed` (normalized reason) - `result_downloaded` -
`result_shared` - `favorite_added` / `favorite_removed` - `recipe_saved`
/ `recipe_reused` - `project_reopened` - `smart_action_selected` -
`pack_started` / `pack_completed`

Useful metrics: - first-generation completion rate - generation success
rate - template-to-generation conversion - 1-day and 7-day return rate -
percentage of users reusing a project/recipe/character - paid conversion
and contribution per returning user - repeat generation rate after a
successful result

Do not claim "Trending" based on data until enough genuine activity
exists.

------------------------------------------------------------------------

## 16. Accessibility, performance, and UI quality

-   Follow current theme and shared design tokens; do not scatter
    hardcoded colors.
-   Ensure text contrast, readable font sizes, semantic labels, and
    sufficiently large tap targets.
-   Support small screens and different font scales without overflow.
-   Avoid expensive network/image work in `build()` or equivalent render
    methods.
-   Cache template thumbnails through the existing image cache.
-   Use lazy lists/grids for long catalogues.
-   Use placeholders/skeletons that do not look like completed results.
-   Avoid repeated randomization/state resets during rebuilds.
-   Handle no network, slow network, empty lists, expired media and
    missing thumbnails.
-   Keep animations subtle and consistent with the existing app.
-   Respect Android back navigation and bottom-sheet dismissal behavior.

------------------------------------------------------------------------

## 17. Implementation phases and acceptance criteria

### Phase 0 --- Audit (must happen first)

-   Map the current repository and identify reusable components.
-   Confirm current Explore banner behavior and template config source.
-   Confirm job/credit/history persistence behavior.
-   Produce a file-by-file implementation plan.
-   No functional changes yet.

### Phase 1 --- Explore polish and workflow templates

-   Preserve the existing banner and tools.
-   Add outcome-based shortcuts and improved categories/sections.
-   Improve template schema/details and ensure every card launches the
    existing flow.
-   Add correct credit display and required-input validation.
-   Acceptance: no duplicate generation architecture; all template taps
    reach valid workflows; existing banner still advertises five random
    templates.

### Phase 2 --- Smart next actions and history/project entry

-   Add contextual next actions after successful jobs.
-   Reuse or improve history/gallery.
-   Add the state-aware "Continue creating" / "Your shortcuts" / starter
    empty state.
-   Preserve original results when generating variants/edits.
-   Acceptance: returning users can reopen/reuse a successful result
    without manually finding/re-uploading it where supported.

### Phase 3 --- Favorites and recipes

-   Add favorites and recipe saving/reuse using existing persistence.
-   Recalculate cost at use time.
-   Acceptance: favorites survive app restart; recipes reopen the
    correct tool with values prefilled.

### Phase 4 --- My Characters and reference collections

-   Add explicit saved references and character selection.
-   Enforce provider limits and privacy/deletion behavior.
-   Acceptance: no reference is sent unless the user explicitly selects
    it.

### Phase 5 --- Creator/business packs and export presets

-   Add bounded multi-output flows using existing jobs.
-   Show full cost before submission and per-output status.
-   Acceptance: failures/retries do not double-charge or discard
    successful outputs.

### Phase 6 --- Analytics and iteration

-   Instrument key funnel events.
-   Review real usage before expanding features further.
-   Acceptance: events are privacy-conscious and no fabricated trending
    metrics appear.

------------------------------------------------------------------------

## 18. Required engineering process for Cursor

For each phase:

1.  Inspect relevant files before editing.
2.  State the files/classes to change and the intended behavior.
3.  Reuse existing components, theme tokens, configuration, persistence,
    and job services.
4.  Make a small, cohesive implementation.
5.  Run formatter, analyzer/linter, and relevant tests.
6.  Fix regressions before proceeding.
7.  Summarize files changed, behavior added, test commands/results, and
    any remaining manual checks.
8.  Do not claim tests passed unless actually run.
9.  Do not silently change backend contracts or provider request
    schemas.
10. If an API capability is uncertain, inspect the current repository
    integration and provider docs; implement only verified behavior.

### Definition of done

-   Existing core generation/editing/video tools still work.
-   Existing banner still displays its five-template random slideshow.
-   No excluded feature (video extension, brush/tap-to-edit, mask UI,
    preview-before-spend) is introduced.
-   All new flows use the current job/credit system.
-   Every new UI state has loading, empty, error and success behavior
    where applicable.
-   Costs are consistent and visible before submission.
-   No fake data, fabricated trending, or placeholder history is
    presented as real.
-   The app formats, analyzes/builds, and relevant tests pass, or any
    failures are explicitly reported.

------------------------------------------------------------------------

## 19. Provider references for the mask decision

-   Qwen Image 2.1 official repository (model-level local editing and
    masks): https://github.com/QwenLM/Qwen-Image-2.1
-   Kie AI Qwen image-edit endpoint schema:
    https://docs.kie.ai/market/qwen/image-edit
-   Kie AI Qwen Image 2.1 product page: https://kie.ai/qwen-image-2.1

**Final instruction:** Start with Phase 0 repository reconnaissance. Do
not implement all phases in one pass. After the audit, implement Phase 1
only, report the exact files changed and test results, and wait for
review before moving to Phase 2.
