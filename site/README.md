# Beseda site — unpublished

This directory is the local source for the product, support and privacy pages. It is **not published**; there is no public URL. Do not use a local preview address as an App Store URL.

## Local checks (no account or network required)

From the repository root, after the pages exist:

```sh
python3 -m http.server 8765 --directory site
```

Visit `http://127.0.0.1:8765/` only when an interactive preview is safe; stop the server with Ctrl-C. Check product, support and privacy navigation, keyboard focus, narrow and wide layouts, text contrast, page titles and descriptions, and that no purchase link, tracking, form or placeholder contact address is presented as real. For source-only checks (including unattended/night work):

```sh
find site -type f -maxdepth 2 -print
rg -n 'href=|src=|<title>|name="description"|TODO' site --glob '*.html'
```

Inspect every local `href`/`src` target and fragment against the files and IDs; inspect external links deliberately. These commands list candidates, not a link validator. Do not launch a browser or render a screenshot unattended: visual capture is parked until the ios-kit documents a proven browser pattern that creates no OS window. Do not add a headless-rendering workaround here.

## Owner gates before publication

- Supply a real support contact address and approve its publication; replace any TODO on the support page.
- Choose and control the hosting repository and domain (or approve the host-provided domain). No domain or host has been selected.
- Approve the final product copy and privacy policy against the actual store build, including optional remote processing, retention, deletion, backups and recording consent.
- Supply the final Mac App Store URL when the listing exists. Until then, keep the product page free of a purchase CTA.

## Deployment route, only after approval

Proposed concrete route: **GitHub Pages from a dedicated public repository, deploying from its root `main` branch**. These are instructions, not authorization to create a repository, push, register a domain or publish now.

1. Resolve every gate above and rerun the local checks. Ensure `site/index.html`, `site/support.html`, `site/privacy.html` and their relative assets exist; confirm the actual filenames before proceeding. Review the public repository contents so only intended site files are exposed.
2. Owner creates or designates the public GitHub repository. Copy only the reviewed contents of `site/` into its root (not the whole app repository), commit and push to `main` **after explicit publication approval**.
3. In that repository's **Settings → Pages → Build and deployment**, select **Deploy from a branch**, branch `main`, folder `/ (root)`, and save. Wait for the Pages deployment to succeed. GitHub supplies a `https://<owner>.github.io/<repo>/` URL unless the owner configures a custom domain. If a custom domain is approved, configure it in Pages and set the DNS records exactly as GitHub's current Pages instructions require; wait for DNS and HTTPS provisioning, then enforce HTTPS. Do not guess the owner's domain here.
4. Open the deployed product, `/support.html` and `/privacy.html` under the actual Pages base URL; check successful responses, navigation, asset paths, metadata, mobile layout, contact address, privacy text and HTTPS. Check both canonical link metadata (if present) and the final browser URL point to the chosen HTTPS origin, not localhost or an unapproved domain. A project Pages path includes `/<repo>/`: root-relative links may break there. Fix and redeploy before handing off any URL.
5. Give the **verified, stable HTTPS support and privacy URLs** to the App Store Connect listing owner for the Support URL and Privacy Policy URL fields. Verify those exact URLs without authentication in a fresh session before submission; retain the final product URL for release materials. Add a store link to the page only after the actual store URL is supplied and verified.

GitHub Pages is public hosting, not an access-controlled preview. Never use a preview deployment for real conversation data or private owner details.
