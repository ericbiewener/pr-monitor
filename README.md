# PR Monitor

A small native macOS menu bar app for GitHub Enterprise pull requests. It checks every five minutes and keeps the 30 most recent notifications in the menu. Click a notification or menu item to open its PR.

"My PRs" means open PRs authored by `GHE_USERNAME` and open PRs whose description contains a GitHub-style `@GHE_USERNAME` mention. Once found, a PR stays tracked until it closes, so merges and merge queue removals can still be detected after it disappears from open search results.

## Set up

Requires macOS 13 or later and Apple's Swift command line tools or Xcode.

1. Create `~/.config/pr-monitor/.env` using [.env.example](.env.example):

   ```sh
   mkdir -p ~/.config/pr-monitor
   cp .env.example ~/.config/pr-monitor/.env
   chmod 600 ~/.config/pr-monitor/.env
   ```

2. Set `GHE_URL` to the HTTPS web URL of your GitHub Enterprise Server, `GHE_TOKEN` to a token that can read the relevant private repositories and their checks, and `GHE_USERNAME` to your GitHub login. `https://github.com` also works for GitHub Enterprise Cloud. Keep the token out of version control.

3. Build and open the app:

   ```sh
   ./scripts/build-app.sh
   open 'dist/PR Monitor.app'
   ```

4. Allow notifications when macOS asks. To start it at login, add `dist/PR Monitor.app` in **System Settings → General → Login Items**.

The app first looks for `~/.config/pr-monitor/.env`. When run from this repository's `dist` directory, it also finds the repository's `.env`; this works when opening the app from Finder. When run with `swift run`, it can read `.env` from the current working directory. Set `PR_MONITOR_ENV_FILE` to use another path. If you move the app outside `dist`, use the home config path.

## Notification rules

- **Checks passed or failed:** The app reads both check runs and commit statuses for the PR head commit. It waits while any are pending. A completed check run with a conclusion other than `success`, `neutral`, or `skipped`, or a non-success commit status, makes the result a failure. A new commit or a newly observed pending run can produce another completion notification.
- **Merged:** A previously tracked PR changes to merged.
- **Removed from merge queue:** A PR had a GraphQL `mergeQueueEntry` on one poll and has none on a later poll. A merge produces only the merge notification.

The first successful poll records current state without sending old notifications. Later polls notify on changes. If a PR enters and leaves the queue entirely between two polls, the app cannot observe that transition. GitHub Enterprise Server must expose the `PullRequest.mergeQueueEntry` GraphQL field for queue monitoring; if it does not, the menu shows the API error while check and merge monitoring continue.

State and recent notifications are stored in `~/Library/Application Support/PRMonitor/state.json`. The token is read from `.env` and is not stored there.

## If alerts do not appear

macOS can accept an alert but delay or hide its banner. In **System Settings → Notifications → PR Monitor**, enable desktop alerts and turn off **Summarize notifications** for immediate delivery. **Do Not Disturb** in **System Settings → Focus** also silences banners. The menu keeps the event even when macOS does not show a banner.
