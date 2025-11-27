# 🛠️ Gerrit Environment Variables Checkpoint Action

A GitHub Action that checkpoints Gerrit environment variables for use in downstream workflows. This action captures important Gerrit-related metadata and stores it in files for persistence across job boundaries.

## 📋 Description

This action captures and persists Gerrit environment variables by writing them to individual files in a `fdio-gerrit-vars/` directory. This is particularly useful in CI/CD pipelines where Gerrit integration is required and variables need to be preserved across different workflow steps or jobs.

## 🔧 Features

- ✅ Captures all essential Gerrit environment variables
- ✅ Stores variables in individual files for easy access
- ✅ Provides formatted console output for debugging
- ✅ Creates a structured directory for variable storage
- ✅ Automatically uploads variables as workflow artifact
- ✅ Customizable TUI output formatting

## 📥 Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `TUI_LINE` | Delimiter line for TUI output formatting | No | `*******************************************************************` |

## 📤 Outputs

This action creates the following files in the `fdio-gerrit-vars/` directory and automatically uploads them as a workflow artifact named `fdio-gerrit-vars`:

| File | Content | Description |
|------|---------|-------------|
| `gerrit-branch` | `$GERRIT_BRANCH` | Target branch for the change |
| `gerrit-change-id` | `$GERRIT_CHANGE_ID` | Unique identifier for the change |
| `gerrit-change-number` | `$GERRIT_CHANGE_NUMBER` | Sequential number assigned to the change |
| `gerrit-change-url` | `$GERRIT_CHANGE_URL` | Direct URL to the Gerrit change |
| `gerrit-event-type` | `$GERRIT_EVENT_TYPE` | Type of Gerrit event that triggered the action |
| `gerrit-patchset-number` | `$GERRIT_PATCHSET_NUMBER` | Revision number of the patchset |
| `gerrit-patchset-revision` | `$GERRIT_PATCHSET_REVISION` | SHA of the patchset revision |
| `gerrit-project` | `$GERRIT_PROJECT` | Name of the Gerrit project |
| `gerrit-refspec` | `$GERRIT_REFSPEC` | Git refspec for fetching the change |

## 🚀 Usage

### Basic Usage

```yaml
- name: Checkpoint Gerrit Variables
  uses: fdio/.github/.github/actions/gerrit-env-vars-checkpoint@main
```

### With Custom TUI Line

```yaml
- name: Checkpoint Gerrit Variables
  uses: fdio/.github/.github/actions/gerrit-env-vars-checkpoint@main
  with:
    TUI_LINE: "=========================================="
```

### Complete Workflow Example

```yaml
name: CI Pipeline with Gerrit Integration

on:
  workflow_dispatch:

jobs:
  checkpoint:
    runs-on: self-hosted
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Checkpoint Gerrit Variables
        uses: ./.github/actions/gerrit-env-vars-checkpoint
        with:
          TUI_LINE: "--- Gerrit Variables ---"

      - name: Use checkpointed variables
        run: |
          echo "Working with change: $(cat fdio-gerrit-vars/gerrit-change-number)"
          echo "Branch: $(cat fdio-gerrit-vars/gerrit-branch)"
          echo "Project: $(cat fdio-gerrit-vars/gerrit-project)"

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: gerrit-variables
          path: fdio-gerrit-vars/
```

## 📋 Prerequisites

This action expects the following Gerrit environment variables to be available:

- `GERRIT_BRANCH`
- `GERRIT_CHANGE_ID`
- `GERRIT_CHANGE_NUMBER`
- `GERRIT_CHANGE_URL`
- `GERRIT_EVENT_TYPE`
- `GERRIT_PATCHSET_NUMBER`
- `GERRIT_PATCHSET_REVISION`
- `GERRIT_PROJECT`
- `GERRIT_REFSPEC`

These are typically set by Gerrit trigger plugins or CI/CD systems that integrate with Gerrit.

## � Artifact Upload

The action automatically uploads the `fdio-gerrit-vars/` directory as a workflow artifact with the name `fdio-gerrit-vars`. This artifact can be:

- Downloaded from the GitHub Actions UI
- Accessed by subsequent jobs in the same workflow
- Used by downstream workflows (especially useful with `workflow_run` triggers)
- Retrieved via the GitHub API for external processing

The upload uses `actions/upload-artifact@v4` with `if-no-files-found: error` to ensure the checkpoint operation succeeded.

## �🔍 Console Output

The action provides formatted console output showing all captured variables:

```
*******************************************************************
Successfully checkpointed Gerrit environment variables:
GERRIT_BRANCH: main
GERRIT_CHANGE_ID: I1234567890abcdef
GERRIT_CHANGE_NUMBER: 12345
GERRIT_CHANGE_URL: https://gerrit.example.com/c/project/+/12345
GERRIT_EVENT_TYPE: patchset-created
GERRIT_PATCHSET_NUMBER: 2
GERRIT_PATCHSET_REVISION: abc123def456
GERRIT_PROJECT: my-project
GERRIT_REFSPEC: refs/changes/45/12345/2
*******************************************************************
```

## 🗂️ File Structure

After running this action, the following directory structure will be created:

```
fdio-gerrit-vars/
├── gerrit-branch
├── gerrit-change-id
├── gerrit-change-number
├── gerrit-change-url
├── gerrit-event-type
├── gerrit-patchset-number
├── gerrit-patchset-revision
├── gerrit-project
└── gerrit-refspec
```

## 🔄 Use Cases

- **Multi-job workflows**: Share Gerrit context between different jobs via artifacts
- **Workflow triggers**: Pass Gerrit metadata to `workflow_run` triggered workflows
- **Artifact generation**: Include Gerrit metadata in build artifacts for traceability
- **Downstream processing**: Pass Gerrit information to external systems via artifact download
- **Debugging**: Persistent storage of Gerrit variables for troubleshooting
- **Conditional logic**: Use Gerrit variables in subsequent workflow steps
- **Cross-workflow communication**: Enable workflows to access Gerrit context from triggering workflows

## 🛡️ Error Handling

The action uses `set -euo pipefail` for strict error handling:
- **`-e`**: Exit immediately on any command failure
- **`-u`**: Treat unset variables as errors
- **`-o pipefail`**: Fail on any command in a pipeline that fails

## 📝 Notes

- The action creates the `fdio-gerrit-vars/` directory if it doesn't exist
- Each variable is stored in a separate file for easy individual access
- The directory is automatically uploaded as a workflow artifact named `fdio-gerrit-vars`
- The action is designed for self-hosted runners with Gerrit integration
- All files are created in the current working directory
- The artifact upload will fail if no files are created, ensuring checkpoint integrity
