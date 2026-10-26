//! Types shared between Dart and Rust for Galileo Flutter integration.
//! All types here are used by flutter_rust_bridge_codegen.
use flutter_rust_bridge::frb;

use crate::core::camera::Projection;
use std::f64;

#[derive(Debug, Clone, Copy, PartialEq)]
/// Geographic position with latitude and longitude coordinates.
#[frb(dart_code = r#"
  GeoLocation operator +(GeoLocation other) {
    double newLat = latitude + other.latitude;
    double newLng = longitude + other.longitude;
    return _normalize(newLat, newLng);
  }

  GeoLocation operator -(GeoLocation other) {
    double newLat = latitude - other.latitude;
    double newLng = longitude - other.longitude;
    return _normalize(newLat, newLng);
  }

  static GeoLocation _normalize(double lat, double lng) {
    while (lat > 90.0 || lat < -90.0) {
      if (lat > 90.0) {
        lat = 180.0 - lat;
        lng += 180.0;
      } else if (lat < -90.0) {
        lat = -180.0 - lat;
        lng += 180.0;
      }
    }

    double shiftLng = lng + 180.0;
    double wrappedLng = (shiftLng % 360.0 + 360.0) % 360.0;
    lng = wrappedLng - 180.0;

    return GeoLocation(latitude: lat, longitude: lng);
  }
"#)]
pub struct GeoLocation {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
/// Flutter/Screen with x and y coordinates.
#[frb(dart_code = r#"
  ScreenLocation operator +(ScreenLocation other) => ScreenLocation(x: x + other.x, y: y + other.y);
  ScreenLocation operator -(ScreenLocation other) => ScreenLocation(x: x - other.x, y: y - other.y);
"#)]
pub struct ScreenLocation {
    pub x: f64,
    pub y: f64,
}

const R: f64 = 6378137.0;

fn lat_lon_to_mercator(lat: f64, lon: f64) -> (f64, f64) {
    let lat_rad = lat.to_radians();
    let x = lon.to_radians() * R;
    let y = (std::f64::consts::FRAC_PI_4 + lat_rad / 2.0).tan().ln() * R;
    (x, y)
}

fn mercator_to_lat_lon(x: f64, y: f64) -> (f64, f64) {
    let lat = (2.0 * (y / R).exp().atan() - std::f64::consts::FRAC_PI_2).to_degrees();
    let lon = (x / R).to_degrees();
    (lat, lon)
}

/// Screen position used for points that cannot be projected (behind the camera).
const OFFSCREEN: f64 = -1.0e7;

impl GeoLocation {
    /// Projects onto a `width` x `height` screen showing `vp`, including any
    /// bearing and pitch the viewport carries.
    #[frb(sync)]
    pub fn to_screen(self, height: f64, width: f64, vp: MapViewport) -> ScreenLocation {
        let projection = Projection::from_viewport(&vp, width, height);
        let (mx, my) = lat_lon_to_mercator(self.latitude, self.longitude);
        let (x, y) = projection.project(mx, my).unwrap_or((OFFSCREEN, OFFSCREEN));
        ScreenLocation { x, y }
    }

    /// Projects many geographic points in one Dart-to-Rust call.
    #[frb(sync)]
    pub fn points_to_screen(
        points: Vec<GeoLocation>,
        height: f64,
        width: f64,
        vp: MapViewport,
    ) -> Vec<ScreenLocation> {
        points
            .into_iter()
            .map(|point| point.to_screen(height, width, vp))
            .collect()
    }
}

impl ScreenLocation {
    #[frb(sync)]
    pub fn to_geographical(self, vp: MapViewport, height: f64, width: f64) -> GeoLocation {
        let (mx, my) = Projection::from_viewport(&vp, width, height).unproject(self.x, self.y);
        let (lat, lng) = mercator_to_lat_lon(mx, my);
        GeoLocation {
            latitude: lat,
            longitude: lng,
        }
    }
}

/// The part of the map the camera looks at.
///
/// `x_min..x_max` / `y_min..y_max` are Web Mercator meters: the flat, top-down
/// box centered on the camera at the current scale. They do not describe the
/// visible area once the map is rotated or tilted; use [`GeoLocation::to_screen`]
/// and [`ScreenLocation::to_geographical`], which apply `bearing` and `pitch`.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MapViewport {
    pub x_min: f64,
    pub x_max: f64,
    pub y_min: f64,
    pub y_max: f64,
    /// Degrees clockwise from north.
    pub bearing: f64,
    /// Degrees of tilt away from straight down.
    pub pitch: f64,
}

/// Viewport and physical texture size used to produce a rendered map frame.
///
/// Flutter overlays consume these frames so their positions are calculated
/// from the same map state as the texture currently being presented.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RenderedMapFrame {
    /// Monotonically increasing frame identifier for a map session.
    pub sequence: u64,
    pub viewport: MapViewport,
    pub map_size: MapSize,
}

/// Physical size of the map in pixels.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MapSize {
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MapInitConfig {
    pub latlon: GeoLocation,
    pub zoom_level: u32,
    pub map_size: MapSize,
    /// Frames per second for the render loop (default: 30)
    /// Enable multisampling anti-aliasing
    pub enable_multisampling: bool,
    /// Background color as RGBA (0.0-1.0 range)
    pub background_color: GalileoColor,
}

/// Layer configuration for different types of map layers.
#[derive(Debug, Clone, PartialEq)]
pub enum LayerConfig {
    /// OpenStreetMap raster tile layer
    Osm,
    /// Custom raster tile layer with URL template
    RasterTiles {
        url_template: String,
        attribution: Option<String>,
    },
    VectorTiles {
        url_template: String,
        style_json: String,
        attribution: Option<String>,
    },
    /// Layer to render polygons
    PolygonLayer {
        /// Stores the Polygon features to be rendered
        features: Vec<Polygon>,
    },
    PointLayer {
        /// Stores the Point features to be rendered
        features: Vec<Point>,
    },
    /// Placeholder variant handled by flutter
    WidgetLayer,
}

/// Closed geographic polygon with fill/stroke styling.
/// Usage:
///   Polygon(
///     points: [...],
///     style: PolygonStyle(
///       fillColor: GalileoColor(0.2,0.5,0.9,0.8),
///       strokeColor: GalileoColor(1.0,1.0,1.0,1.0),
///       strokeWidth: 2.0,
///       strokeOffset: 0.0,
///     ),
///   )
#[derive(Clone, Debug, PartialEq)]
pub struct Polygon {
    pub points: Vec<GeoLocation>,
    pub style: PolygonStyle,
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct PolygonStyle {
    /// fillColor also as RGBA (0.0-1.0 range)
    pub fill_color: GalileoColor,
    /// fillColor also as RGBA (0.0-1.0 range)
    pub stroke_color: GalileoColor,
    /// strokeWidth with (0.0-1.0 range)
    pub stroke_width: f64,
    /// strokeOffset with (0.0-1.0 range)
    pub stroke_offset: f64,
}

#[derive(Clone, Debug)]
pub struct PolygonSymbol {}

/// Points with properties for colors
/// Usage:
///   Point(
///     coordinate: GeoLocation(latitude:27.7,longitude:85.3),
///     style: PointStyle(
///       fillColor: GalileoColor(0.2,0.5,0.9,0.8),
///       size: 0.8,
///     ),
///   )
#[derive(Clone, Debug, PartialEq)]
pub struct Point {
    pub coordinate: GeoLocation,
    pub style: PointStyle,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PointStyle {
    pub fill_color: GalileoColor,
    pub size: f32,
}

#[derive(Clone, Debug)]
pub struct PointSymbol {}

// Manual type definitions for Dart-friendly versions
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct GalileoColor {
    pub r: f64,
    pub g: f64,
    pub b: f64,
    pub a: f64,
}

/// 2D point in cartesian coordinate space.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point2 {
    pub x: f64,
    pub y: f64,
}

/// 3D point in cartesian coordinate space.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point3 {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

/// 2D vector in cartesian coordinate space.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vector2 {
    pub dx: f64,
    pub dy: f64,
}

/// Mouse button enum.
#[derive(Debug, Copy, Clone, PartialEq)]
pub enum MouseButton {
    /// The button you click when you want to shoot.
    Left,
    /// The button you click when you want to reload.
    Middle,
    /// The button you click when you want to hit with a rifle handle.
    Right,
    /// The button you click when you are a pro gamer and want to look cool.
    Other,
}

/// Mouse button state.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum MouseButtonState {
    /// Button is pressed.
    Pressed,
    /// Button is not pressed.
    Released,
}

/// State of all mouse buttons.
#[derive(Debug, Copy, Clone)]
pub struct MouseButtonsState {
    /// State of the left mouse button.
    pub left: MouseButtonState,
    /// State of the middle mouse button.
    pub middle: MouseButtonState,
    /// State of the right mouse button.
    pub right: MouseButtonState,
}

/// State of the mouse at the moment of the event.
#[derive(Debug, Clone)]
pub struct MouseEvent {
    /// Pointer position on the screen in pixels from the top-left corner.
    pub screen_pointer_position: Point2,
    /// State of the mouse buttons.
    pub buttons: MouseButtonsState,
}

/// User interaction event.
#[derive(Debug, Clone)]
pub enum UserEvent {
    /// A mouse button was pressed.
    ButtonPressed(MouseButton, MouseEvent),
    /// A mouse button was released.
    ButtonReleased(MouseButton, MouseEvent),
    /// A mouse button was clicked.
    Click(MouseButton, MouseEvent),
    /// A double click was done.
    DoubleClick(MouseButton, MouseEvent),
    /// Mouse pointer moved.
    PointerMoved(MouseEvent),
    /// Drag started.
    DragStarted(MouseButton, MouseEvent),
    /// Mouse pointer moved after drag started was consumed.
    Drag(MouseButton, Vector2, MouseEvent),
    /// Mouse button was released while dragging.
    DragEnded(MouseButton, MouseEvent),
    /// Scroll event is called.
    Scroll(f64, MouseEvent),
    /// Zoom is called around a point.
    Zoom(f64, Point2),
    /// Rotate the map by this many degrees clockwise around a screen point.
    Rotate(f64, Point2),
    /// Tilt the map by this many degrees (positive tilts towards the horizon).
    Pitch(f64),
}
