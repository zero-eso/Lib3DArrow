# Lib3DArrow

Lib3DArrow is an Elder Scrolls Online library for rendering a 3D directional arrow, distance text, and a world marker toward a target map position.

This repository preserves the original library by [kadeer](https://www.esoui.com/forums/member.php?action=getinfo&userid=34300) and carries the modernization work maintained by Zero.

## Credit

Full creation credit for Lib3DArrow belongs to [kadeer](https://www.esoui.com/forums/member.php?action=getinfo&userid=34300).

Modernization changes in this repository were done by Zero:

- removed the hard `Lib3D` dependency entirely
- updated the library to use the native ESO render-space and camera APIs
- kept `LibGPS` for map measurement and coordinate conversion work
- added optional integration support for `SkyShards` and `LoreBooks`
- added settings, including per-source colour options for tracked content

## What Changed

The modernized build keeps the original goal of Lib3DArrow intact while removing the dependency on `Lib3D`.

Current behavior:

- native ESO render-space APIs handle 3D placement and camera orientation
- `LibGPS` handles local/global map measurements
- `SkyShards` and `LoreBooks` are optional integrations, not hard requirements
- the integration tracker can point at the nearest unknown SkyShard or Shalidor LoreBook
- the managed tracker has options for enablement, source selection, visibility, refresh interval, and source colours

## Dependencies

Required:

- `LibGPS`

Optional:

- `SkyShards`
- `LoreBooks`
- `LibAddonMenu-2.0`

If the optional addons are not installed, Lib3DArrow still functions as a standalone library.

## Notes

- SkyShards integration targets unknown shards.
- LoreBooks integration currently targets unknown Shalidor books.
- The arrow can be rendered flat, but true terrain clamping is still limited by the native addon API surface.
