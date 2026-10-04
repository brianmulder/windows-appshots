# Windows AppShots cloud development

Use Windows AppShots as the project name. The GitHub repository is the source home;
installed Windows plugin caches and saved AppShots are runtime data, not development sources.

Cloud setup uses Node 24, matching the existing release workflow. There are no declared
package dependencies or install lifecycle scripts, so no npm install, native build, Codex
installation, credentials, browser, .NET SDK, or saved AppShot upload is required for this lane.

```sh
node --version
node --check scripts/cloud-check.mjs
node scripts/cloud-check.mjs
```

This is an explicitly scoped seven-test portable lane using synthetic temporary bundles.
It does not replace npm test or Windows release acceptance. The two watcher tests invoke
the native Windows helper; native capture, watcher, installer and UI Automation acceptance
remain on Windows through the existing release workflow. Do not alter application behavior
or skip those Windows gates to make a cloud run appear complete.

Initial source validated for preparation: main commit
273a1412487e7643aaef9d3918687556c3b4fb84. The old Windows checkout was clean at
92e289c234b6ee1db905a15e4eba78fd843966ba and had no unpublished work. Use current
published main rather than uploading that older copy. No cloud run is claimed by local tests.

After the saved cloud environment passes the portable lane and its task entrypoint is verified,
designate it the one default development home. Keep the Windows deployment and native acceptance
explicit. Retire old development project entries reversibly only after reviewing their current
state; preserve saved AppShots and any installed runtime dependencies.
