# Missing assets

No required assets are missing. Both original SVG files were copied verbatim from `/home/tushar/Documents/code/tasbih_web` to `assets/branding/` and verified against GitHub. All source-referenced Google Fonts are bundled with their licenses under `assets/fonts/`.

Launcher rasters were generated from the actual SVGs, including their original `33` text. Android legacy and adaptive icons, opaque iOS icons, macOS assets, Web icons, a Windows ICO, and a Linux window icon are included.

Small licensed Noto Emoji and DejaVu symbol subsets ensure the original prayer emoji, flame, check/cross and chevron render without network requests. Roboto is bundled solely because Flutter Web may otherwise fetch its default fallback font from Google; the primary UI uses the original Amiri and IBM Plex Sans Arabic fonts.

The web service worker references `all_in_one.html`, but that file does not exist in the authoritative checkout/GitHub repository. It is not an app asset and is not needed by the native implementation; no user action is required.

No assets or resources need to be supplied manually. Distribution signing credentials are separate from visual assets and are not included.
