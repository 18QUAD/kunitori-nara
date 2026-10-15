"""Prepare zoom-11 DEM hillshade (~63 m) for uniform national image baking.

Raw and intermediate images remain in data/raw, outside the release bundle.
Uses the standard environment proxy and TLS verification via urllib.
"""
import import_national_relief as importer

if __name__ == '__main__':
    importer.ZOOM = 11
    importer.OUT = importer.ROOT/'data/raw/fine_relief'
    importer.CACHE = importer.ROOT/'data/raw/fine_dem_z11'
    importer.OUT.mkdir(parents=True, exist_ok=True)
    importer.CACHE.mkdir(parents=True, exist_ok=True)
    importer.main()
