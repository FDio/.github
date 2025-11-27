# 🛠️ Gerrit Environment Variables Restore

This GitHub Action restores Gerrit environment variables from a checkpoint artifact that was previously saved. It's designed to work in multi-job workflows where Gerrit-related data needs to be passed between jobs.

## Overview

The action downloads a `fdio-gerrit-vars` artifact from a workflow run and extracts the stored Gerrit environment variables, making them available for subsequent workflow steps.

## Usage

```yaml
- name: Restore Gerrit Environment Variables
  uses: fdio/.github/.github/actions/gerrit-env-vars-restore@main
  with:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    TUI_LINE: "*******************************************************************"
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `GITHUB_TOKEN` | GitHub token for API access to download artifacts | Yes | - |
| `TUI_LINE` | Delimiter line for TUI output formatting | No | `"*******************************************************************"` |

## Environment Variables Restored

This action restores the following Gerrit-related environment variables:

- `GERRIT_BRANCH` - The target branch for the Gerrit change
- `GERRIT_CHANGE_ID` - Unique identifier for the Gerrit change
- `GERRIT_CHANGE_NUMBER` - Numeric identifier for the Gerrit change
- `GERRIT_CHANGE_URL` - Direct URL to the Gerrit change
- `GERRIT_EVENT_TYPE` - Type of Gerrit event that triggered the workflow
- `GERRIT_PATCHSET_NUMBER` - Current patchset number
- `GERRIT_PATCHSET_REVISION` - SHA revision of the patchset
- `GERRIT_PROJECT` - Name of the Gerrit project
- `GERRIT_REFSPEC` - Git refspec for the change

## Prerequisites

This action requires:

1. A previous job that created and uploaded a `fdio-gerrit-vars` artifact
2. The workflow must be triggered by a `workflow_run` event
3. Access to `secrets.GITHUB_TOKEN` which must be passed as the `GITHUB_TOKEN` input

## Workflow Context

This action is typically used in workflows triggered by `workflow_run` events, where it needs to restore context from the original triggering workflow. The artifact contains files with the saved environment variable values.

## Example Workflow

```yaml
name: Process Gerrit Change
on:
  workflow_run:
    workflows: ["Initial Gerrit Processing"]
    types:
      - completed

jobs:
  process-change:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Restore Gerrit Environment Variables
        uses: ./.github/actions/gerrit-env-vars-restore
        with:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Use Gerrit Variables
        run: |
          echo "Processing change: $GERRIT_CHANGE_NUMBER"
          echo "Branch: $GERRIT_BRANCH"
          echo "Project: $GERRIT_PROJECT"
```

## Error Handling

The action includes comprehensive error handling:

- Validates artifact existence before download
- Falls back to matrix artifacts (e.g., `fdio-gerrit-vars-*`) if the main artifact is not found
- Provides detailed debugging information about available artifacts
- Exits with error code if required files are not found

## Artifact Structure

The expected artifact (`fdio-gerrit-vars`) should contain the following files:

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

Each file contains the corresponding environment variable value as plain text.

## Security Considerations

- Requires `GITHUB_TOKEN` to be explicitly passed as input for GitHub API access
- Only accesses artifacts from the same repository
- Sanitizes input by removing newlines and carriage returns from restored values
- Token is only used for artifact download operations within the same repository

## Troubleshooting

If the action fails:

1. Check that the triggering workflow successfully created the `fdio-gerrit-vars` artifact
2. Verify the workflow is triggered by a `workflow_run` event
3. Ensure `GITHUB_TOKEN` input is provided with `${{ secrets.GITHUB_TOKEN }}`
4. Verify the token has appropriate permissions for artifact access
5. Check the action logs for detailed artifact information

The action provides extensive logging to help diagnose issues with artifact discovery and download.
