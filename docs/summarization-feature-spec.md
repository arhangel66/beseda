# Feature Specification: Conversation Summarization

## Overview
Add a summarization feature to the call details view, allowing users to generate high-level summaries, key points, and action items from their transcripts. The feature must support multiple providers, with a strong emphasis on local LLM execution for privacy.

## Current State
- [x] Transcription (ASR) and Diarization are implemented.
- [x] Call details (transcript) are displayed in a `CallDetailView`.
- [ ] No summary storage in `StoredCallDetail` or `CallStore`.
- [ ] No mechanism for sending text to LLMs.
- [ ] No settings for AI models or prompts.

## Architecture

### 1. Summarization Layer
We will introduce a provider-based architecture to support different backends.

#### `SummarizationProvider` Protocol
Defines the interface for any summarization engine.
- `name`: Display name.
- `iconName`: SF Symbol name.
- `summarize(text: String, prompt: String) async throws -> String`

#### Supported Providers
1. **`LocalLlamaProvider`**: Communicates with a local server (e.g., Ollama via HTTP API). 
2. **`OpenAIProvider`**: Communicates with OpenAI API.
3. **`AnthropicProvider`**: Communicates with Claude API.
4. **`MockProvider`**: Returns dummy data for UI development.

#### `SummarizationService`
Orchestrates the process:
- Fetches the selected provider from `AppSettings`.
- Handles retry logic and error mapping.
- Manages the workflow of: `Text -> Prompt + Text -> LLM -> Result`.

### 2. Data Model Changes
#### `StoredCallDetail`
- `summaryText: String?` - Stores the generated summary.

#### `CallStore`
- Update schema to include `summaryText` in the database for each call.

### 3. User Interface (UI)

#### Settings (`AppSettings`)
- `summarizationProvider`: Enum (`local`, `openai`, `anthropic`, `none`).
- `localModelEndpoint`: URL (default: `http://localhost:11434`).
- `localModelName`: Model string (e.g., `llama3`).
- `customPrompt`: Text field for user-defined prompts.

#### Call Detail View (`CallDetailView`)
- **New Tab**: `summary` (added to `CallDetailTab`).
- **Summary View**: A new SwiftUI view showing:
    - A "Magic" icon (✨) to trigger generation if empty.
    - Markdown-rendered summary text.
- **Action Button**: A button in the header or `TranscriptLines` to "Generate Summary".

---

## Implementation Roadmap

### Phase 1: Data & Core (The Foundation)
- [ ] **Step 1.1**: Update `StoredCallDetail` and `CallStore` to support saving/loading `summaryText`.
- [ ] **Step 1.2**: Define `SummarizationProvider` protocol and `SummarizationService`.
- [ ] **Step 1.3**: Implement `MockProvider` for safe testing.

### Phase 2: Local LLM & Settings (The Core Feature)
- [ ] **Step 2.1**: Implement `LocalLlamaProvider` (Ollama compatible).
- [ ] **Step 2.2**: Update `AppSettings` with provider and model configuration.
- [ ] **Step 2.3**: Build the Settings UI for AI configuration.

### Phase 3: User Interface (The Experience)
- [ ] **Step 3.1**: Add `summary` to `CallDetailTab`.
- [ ] **Step 3.2**: Create `CallSummaryView` (Markdown-capable view).
- [ ] **Step 3.3**: Integrate "Generate" button into `CallDetailView`.
- [ ] **Step 3.4**: Add progress indicator/spinner during generation.

### Phase 4: Polish & Refinement
- [ ] **Step 4.1**: Implement prompt templates (Default "Smart Summary" vs "Action Items").
- [ ] **Step 4.2**: Handle long transcript edge-cases (chunking/token limits).
- [ ] **Step 4.3**: Final UI polish and error handling for connection issues.
