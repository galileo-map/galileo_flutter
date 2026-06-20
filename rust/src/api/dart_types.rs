//! Types shared between Dart and Rust for Galileo Flutter integration.
//! All types here are used by flutter_rust_bridge_codegen.

use flutter_rust_bridge::frb;
use galileo::galileo_types;
use std::f64;

#[derive(Debug, Clone, Copy, PartialEq)]
/// Geographic position with latitude and longitude coordinates.
pub struct GeoLocation {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
/// Flutter/Screen with x and y coordinates.
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

#[frb(dart_code = r#"
  GeoLocation operator +(GeoLocation other) {
    double newLat = this.latitude + other.latitude;
    double newLng = this.longitude + other.longitude;
    return _normalize(newLat, newLng);
  }

  GeoLocation operator -(GeoLocation other) {
    double newLat = this.latitude - other.latitude;
    double newLng = this.longitude - other.longitude;
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
impl GeoLocation {
    #[frb(sync)]
    pub fn to_screen(self, height: f64, width: f64, vp: MapViewport) -> ScreenLocation {
        let (mx, my) = lat_lon_to_mercator(self.latitude, self.longitude);
        let dx = vp.x_max - vp.x_min;
        let dy = vp.y_max - vp.y_min;
        ScreenLocation {
            x: if dx == 0.0 {
                0.0
            } else {
                (mx - vp.x_min) / dx * width
            },
            y: if dy == 0.0 {
                0.0
            } else {
                (vp.y_max - my) / dy * height
            },
        }
    }
}
#[frb(dart_code = r#"
  ScreenLocation operator +(ScreenLocation other) => ScreenLocation(x: x + other.x, y: y + other.y);
  ScreenLocation operator -(ScreenLocation other) => ScreenLocation(x: x - other.x, y: y - other.y);
"#)]
impl ScreenLocation {
    #[frb(sync)]
    pub fn to_geographical(self, vp: MapViewport, height: f64, width: f64) -> GeoLocation {
        let mx = vp.x_min
            + if width == 0.0 {
                0.0
            } else {
                (self.x / width) * (vp.x_max - vp.x_min)
            };
        let my = vp.y_max
            - if height == 0.0 {
                0.0
            } else {
                (self.y / height) * (vp.y_max - vp.y_min)
            };
        let (lat, lng) = mercator_to_lat_lon(mx, my);
        GeoLocation {
            latitude: lat,
            longitude: lng,
        }
    }
}

/// Map viewport configuration including center, zoom, and rotation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MapViewport {
    pub x_min: f64,
    pub x_max: f64,
    pub y_min: f64,
    pub y_max: f64,
}

impl MapViewport {
    #[frb(ignore)]
    pub fn from_rect(rect: &galileo_types::cartesian::Rect) -> Self {
        Self {
            x_min: rect.x_min(),
            x_max: rect.x_max(),
            y_min: rect.y_min(),
            y_max: rect.y_max(),
        }
    }
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
    pub background_color: (f32, f32, f32, f32),
}

impl Default for MapInitConfig {
    fn default() -> Self {
        Self {
            latlon: GeoLocation {
                latitude: 0.0,
                longitude: 0.0,
            },
            zoom_level: 10,
            map_size: MapSize {
                width: 800,
                height: 600,
            },
            enable_multisampling: true,
            background_color: (0.1, 0.2, 0.3, 1.0),
        }
    }
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
    ///Placeholder variant for flutter based widgets layer
    WidgetLayer,
}

/// Closed geographic polygon with fill/stroke styling.
/// Usage:
///   Polygon(
///     points: [(27.7,85.3), ...],
///     style: PolygonStyle(
///       fillColor: Color(0.2,0.5,0.9,0.8),
///       strokeColor: Color(1.0,1.0,1.0,1.0),
///       strokeWidth: 2.0,
///       strokeOffset: 0.0,
///     ),
///   )
#[derive(Clone, Debug, PartialEq)]
pub struct Polygon {
    pub points: Vec<GeoLocation>,
    pub style: PolygonStyle,
}

#[derive(Clone, Debug, PartialEq)]
pub struct PolygonStyle {
    /// fillColor also as RGBA (0.0-1.0 range)
    pub fill_color: Color,
    /// fillColor also as RGBA (0.0-1.0 range)
    pub stroke_color: Color,
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
///     coordinate: (27.7,85.3),
///     style: PointStyle(
///       fillColor: (0.2,0.5,0.9,0.8),
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
    pub fill_color: Color,
    pub size: f32,
}

#[derive(Clone, Debug)]
pub struct PointSymbol {}

// Manual type definitions for Dart-friendly versions
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Color {
    pub r: f64,
    pub g: f64,
    pub b: f64,
    pub a: f64,
}

impl Color {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo::Color {
        galileo::Color::rgba(
            (self.r * 255.0) as u8,
            (self.g * 255.0) as u8,
            (self.b * 255.0) as u8,
            (self.a * 255.0) as u8,
        )
    }
}

/// 2D point in cartesian coordinate space.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point2 {
    pub x: f64,
    pub y: f64,
}

impl Point2 {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo_types::cartesian::Point2<f64> {
        galileo_types::cartesian::Point2::new(self.x, self.y)
    }
}

/// 3D point in cartesian coordinate space.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point3 {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

impl Point3 {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo_types::cartesian::Point3<f64> {
        galileo_types::cartesian::Point3::new(self.x, self.y, self.z)
    }
}

/// 2D vector in cartesian coordinate space.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vector2 {
    pub dx: f64,
    pub dy: f64,
}

impl Vector2 {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo_types::cartesian::Vector2<f64> {
        galileo_types::cartesian::Vector2::new(self.dx, self.dy)
    }
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

pub type FeatureId = u64;

impl MouseButton {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo::control::MouseButton {
        match self {
            MouseButton::Left => galileo::control::MouseButton::Left,
            MouseButton::Middle => galileo::control::MouseButton::Middle,
            MouseButton::Right => galileo::control::MouseButton::Right,
            MouseButton::Other => galileo::control::MouseButton::Other,
        }
    }
}

/// Mouse button state.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum MouseButtonState {
    /// Button is pressed.
    Pressed,
    /// Button is not pressed.
    Released,
}

impl MouseButtonState {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo::control::MouseButtonState {
        match self {
            MouseButtonState::Pressed => galileo::control::MouseButtonState::Pressed,
            MouseButtonState::Released => galileo::control::MouseButtonState::Released,
        }
    }
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

impl MouseButtonsState {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo::control::MouseButtonsState {
        galileo::control::MouseButtonsState {
            left: self.left.to_galileo(),
            middle: self.middle.to_galileo(),
            right: self.right.to_galileo(),
        }
    }
}

/// State of the mouse at the moment of the event.
#[derive(Debug, Clone)]
pub struct MouseEvent {
    /// Pointer position on the screen in pixels from the top-left corner.
    pub screen_pointer_position: Point2,
    /// State of the mouse buttons.
    pub buttons: MouseButtonsState,
}

impl MouseEvent {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo::control::MouseEvent {
        galileo::control::MouseEvent {
            screen_pointer_position: self.screen_pointer_position.to_galileo(),
            buttons: self.buttons.to_galileo(),
        }
    }
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
}

impl UserEvent {
    #[frb(ignore)]
    pub fn to_galileo(&self) -> galileo::control::UserEvent {
        match self {
            UserEvent::ButtonPressed(button, event) => {
                galileo::control::UserEvent::ButtonPressed(button.to_galileo(), event.to_galileo())
            }
            UserEvent::ButtonReleased(button, event) => {
                galileo::control::UserEvent::ButtonReleased(button.to_galileo(), event.to_galileo())
            }
            UserEvent::Click(button, event) => {
                galileo::control::UserEvent::Click(button.to_galileo(), event.to_galileo())
            }
            UserEvent::DoubleClick(button, event) => {
                galileo::control::UserEvent::DoubleClick(button.to_galileo(), event.to_galileo())
            }
            UserEvent::PointerMoved(event) => {
                galileo::control::UserEvent::PointerMoved(event.to_galileo())
            }
            UserEvent::DragStarted(button, event) => {
                galileo::control::UserEvent::DragStarted(button.to_galileo(), event.to_galileo())
            }
            UserEvent::Drag(button, vector, event) => galileo::control::UserEvent::Drag(
                button.to_galileo(),
                vector.to_galileo(),
                event.to_galileo(),
            ),
            UserEvent::DragEnded(button, event) => {
                galileo::control::UserEvent::DragEnded(button.to_galileo(), event.to_galileo())
            }
            UserEvent::Scroll(delta, event) => {
                galileo::control::UserEvent::Scroll(*delta, event.to_galileo())
            }
            UserEvent::Zoom(delta, point) => {
                galileo::control::UserEvent::Zoom(*delta, point.to_galileo())
            }
        }
    }
}
