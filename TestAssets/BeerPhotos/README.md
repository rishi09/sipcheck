# Beer Photo Test Assets

These images are for manual simulator/device testing. They are not bundled in
the shipping app. Import them into a booted simulator with:

```bash
xcrun simctl addmedia booted TestAssets/BeerPhotos/*.jpg \
  TestAssets/BeerPhotos/sample-tap-menu.png
```

`sample-tap-menu.svg` and its tracked PNG rendering are generated,
high-contrast OCR fixtures for exercising the menu-ranking flow.

## Sources and licenses

- `beer-bottle-label.jpg` - [Beer Bottle label](https://commons.wikimedia.org/wiki/File:Beer_Bottle_label.jpg), Subhashish Panigrahi, CC BY-SA 3.0.
- `bia-viet-bottle.jpg` - [Bia Viet bottle with beer mug](https://commons.wikimedia.org/wiki/File:Bia_Viet_bottle_with_beer_mug,_Ho_Chi_Minh_City,_2023_(01).jpg), Bahnfrend, CC BY-SA 4.0.
- `orion-draft-bottle.jpg` - [Orion Premium Draft Beer](https://commons.wikimedia.org/wiki/File:Orion_Premium_Draft_Beer,_633_mL_bottle_as_sold_in_Canada.jpg), Yuet Man Lee, CC BY-SA 4.0.

The downloaded files are 1920-pixel Wikimedia thumbnails of the originals.
Redistribution and modifications must retain the applicable attribution and
share-alike license.
