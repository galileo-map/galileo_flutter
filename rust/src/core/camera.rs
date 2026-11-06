//! Camera model kept on the Rust side.
//!
//! MapLibre Native's continuous renderer exposes no camera getters, so the
//! session owns the authoritative camera and pushes it to the renderer with
//! absolute `jumpTo` updates. The same model produces the viewport that
//! Flutter overlays use to position themselves, and [`Projection`] is the one
//! implementation of MapLibre's perspective math shared by gestures
//! (unproject) and overlays (project).

use crate::api::dart_types::{GeoLocation, MapViewport};

/// Edge length of a MapLibre world tile at zoom 0, in pixels.
const TILE_SIZE: f64 = 512.0;
const EARTH_RADIUS: f64 = 6378137.0;
const CIRCUMFERENCE: f64 = 2.0 * std::f64::consts::PI * EARTH_RADIUS;
/// MapLibre's default vertical field of view has `tan(fov / 2) == 1 / 3`, which
/// puts the camera `1.5 * height` pixels from the map center.
const CAMERA_DISTANCE_PER_HEIGHT: f64 = 1.5;
pub const MIN_ZOOM: f64 = 0.0;
pub const MAX_ZOOM: f64 = 22.0;
pub const MAX_PITCH: f64 = 60.0;

/// Maps between Web Mercator meters and screen pixels for a (possibly rotated
/// and tilted) view. Screen space has its origin at the top-left corner.
#[derive(Debug, Clone, Copy)]
pub struct Projection {
    /// Mercator position of the screen center, in meters.
    pub center_x: f64,
    pub center_y: f64,
    /// Screen pixels per meter at the screen center.
    pub scale: f64,
    pub bearing: f64,
    pub pitch: f64,
    pub width: f64,
    pub height: f64,
}

impl Projection {
    pub fn from_viewport(vp: &MapViewport, width: f64, height: f64) -> Self {
        let span = vp.x_max - vp.x_min;
        Self {
            center_x: (vp.x_min + vp.x_max) / 2.0,
            center_y: (vp.y_min + vp.y_max) / 2.0,
            scale: if span == 0.0 { 0.0 } else { width / span },
            bearing: vp.bearing,
            pitch: vp.pitch,
            width,
            height,
        }
    }

    fn distance(&self) -> f64 {
        CAMERA_DISTANCE_PER_HEIGHT * self.height
    }

    /// Mercator meters to screen pixels. Points behind the camera yield `None`.
    pub fn project(&self, mx: f64, my: f64) -> Option<(f64, f64)> {
        let east = (mx - self.center_x) * self.scale;
        let south = -(my - self.center_y) * self.scale;
        let (sin_b, cos_b) = self.bearing.to_radians().sin_cos();
        let x = east * cos_b + south * sin_b;
        let y = -east * sin_b + south * cos_b;
        let (sin_p, cos_p) = self.pitch.to_radians().sin_cos();
        let d = self.distance();
        let depth = d - y * sin_p;
        if depth <= 1e-6 {
            return None;
        }
        let k = d / depth;
        Some((self.width / 2.0 + x * k, self.height / 2.0 + y * cos_p * k))
    }

    /// Screen pixels to Mercator meters on the ground plane. Positions at or
    /// above the horizon are clamped to just below it.
    pub fn unproject(&self, sx: f64, sy: f64) -> (f64, f64) {
        let d = self.distance();
        let (sin_p, cos_p) = self.pitch.to_radians().sin_cos();
        let u = sx - self.width / 2.0;
        let mut v = sy - self.height / 2.0;
        if sin_p > 1e-9 {
            // The horizon sits where `d * cos_p + v * sin_p` reaches zero.
            v = v.max(-d * cos_p / sin_p * 0.999);
        }
        let y = v * d / (d * cos_p + v * sin_p);
        let depth = d - y * sin_p;
        let x = u * depth / d;
        let (sin_b, cos_b) = self.bearing.to_radians().sin_cos();
        let east = x * cos_b - y * sin_b;
        let south = x * sin_b + y * cos_b;
        let scale = if self.scale == 0.0 { 1.0 } else { self.scale };
        (self.center_x + east / scale, self.center_y - south / scale)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Camera {
    /// Center in normalized Web Mercator space; `(0, 0)` is the top-left of the world.
    x: f64,
    y: f64,
    pub zoom: f64,
    /// Degrees clockwise from north, in `(-180, 180]`.
    pub bearing: f64,
    /// Degrees of tilt away from straight down.
    pub pitch: f64,
}

impl Camera {
    pub fn new(center: GeoLocation, zoom: f64) -> Self {
        let lat = center.latitude.clamp(-85.0511, 85.0511).to_radians();
        Self {
            x: ((center.longitude + 180.0) / 360.0).clamp(0.0, 1.0),
            y: ((1.0 - (lat.tan() + 1.0 / lat.cos()).ln() / std::f64::consts::PI) / 2.0)
                .clamp(0.0, 1.0),
            zoom: zoom.clamp(MIN_ZOOM, MAX_ZOOM),
            bearing: 0.0,
            pitch: 0.0,
        }
    }

    pub fn center(&self) -> GeoLocation {
        let n = std::f64::consts::PI * (1.0 - 2.0 * self.y);
        GeoLocation {
            latitude: n.sinh().atan().to_degrees(),
            longitude: self.x * 360.0 - 180.0,
        }
    }

    fn world_size(zoom: f64) -> f64 {
        TILE_SIZE * 2f64.powf(zoom)
    }

    fn meters_per_pixel(&self) -> f64 {
        CIRCUMFERENCE / Self::world_size(self.zoom)
    }

    fn center_meters(&self) -> (f64, f64) {
        (
            (self.x - 0.5) * CIRCUMFERENCE,
            (0.5 - self.y) * CIRCUMFERENCE,
        )
    }

    fn set_center_meters(&mut self, mx: f64, my: f64) {
        self.x = (mx / CIRCUMFERENCE + 0.5).clamp(0.0, 1.0);
        self.y = (0.5 - my / CIRCUMFERENCE).clamp(0.0, 1.0);
    }

    pub fn projection(&self, width: f64, height: f64) -> Projection {
        let (center_x, center_y) = self.center_meters();
        Projection {
            center_x,
            center_y,
            scale: 1.0 / self.meters_per_pixel(),
            bearing: self.bearing,
            pitch: self.pitch,
            width,
            height,
        }
    }

    /// Moves the map so the ground point that was under `(px - dx, py - dy)` ends
    /// up under `(px, py)`, which keeps content glued to a dragged pointer even
    /// when the view is tilted.
    pub fn pan(&mut self, dx: f64, dy: f64, px: f64, py: f64, width: f64, height: f64) {
        let projection = self.projection(width, height);
        let before = projection.unproject(px - dx, py - dy);
        let after = projection.unproject(px, py);
        let (cx, cy) = self.center_meters();
        self.set_center_meters(cx + before.0 - after.0, cy + before.1 - after.1);
    }

    /// Changes the zoom to `zoom` while keeping the ground point under the
    /// screen position `(px, py)` fixed.
    pub fn zoom_to(&mut self, zoom: f64, px: f64, py: f64, width: f64, height: f64) {
        let anchor = self.projection(width, height).unproject(px, py);
        self.zoom = zoom.clamp(MIN_ZOOM, MAX_ZOOM);
        self.keep_anchor(anchor, px, py, width, height);
    }

    /// Multiplies the map resolution by `factor` (below 1 zooms in) around `(px, py)`.
    pub fn zoom_by_resolution(&mut self, factor: f64, px: f64, py: f64, width: f64, height: f64) {
        if !factor.is_finite() || factor <= 0.0 {
            return;
        }
        self.zoom_to(self.zoom - factor.log2(), px, py, width, height);
    }

    /// Rotates by `degrees` clockwise about the ground point under `(px, py)`.
    pub fn rotate_by(&mut self, degrees: f64, px: f64, py: f64, width: f64, height: f64) {
        let anchor = self.projection(width, height).unproject(px, py);
        let mut bearing = (self.bearing + degrees) % 360.0;
        if bearing > 180.0 {
            bearing -= 360.0;
        } else if bearing <= -180.0 {
            bearing += 360.0;
        }
        self.bearing = bearing;
        self.keep_anchor(anchor, px, py, width, height);
    }

    pub fn pitch_by(&mut self, degrees: f64) {
        self.pitch = (self.pitch + degrees).clamp(0.0, MAX_PITCH);
    }

    /// Shifts the center so `anchor` projects to `(px, py)` again.
    fn keep_anchor(&mut self, anchor: (f64, f64), px: f64, py: f64, width: f64, height: f64) {
        let now = self.projection(width, height).unproject(px, py);
        let (cx, cy) = self.center_meters();
        self.set_center_meters(cx + anchor.0 - now.0, cy + anchor.1 - now.1);
    }

    /// The flat box (Web Mercator meters) around the center at the current
    /// scale, plus the orientation. [`Projection::from_viewport`] turns it back
    /// into a full projection at any screen size.
    pub fn viewport(&self, width: f64, height: f64) -> MapViewport {
        let mpp = self.meters_per_pixel();
        let (cx, cy) = self.center_meters();
        MapViewport {
            x_min: cx - width / 2.0 * mpp,
            x_max: cx + width / 2.0 * mpp,
            y_min: cy - height / 2.0 * mpp,
            y_max: cy + height / 2.0 * mpp,
            bearing: self.bearing,
            pitch: self.pitch,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loc(latitude: f64, longitude: f64) -> GeoLocation {
        GeoLocation {
            latitude,
            longitude,
        }
    }

    fn oriented(bearing: f64, pitch: f64) -> Camera {
        let mut camera = Camera::new(loc(10.0, 20.0), 4.0);
        camera.bearing = bearing;
        camera.pitch = pitch;
        camera
    }

    #[test]
    fn center_round_trips() {
        let center = Camera::new(loc(32.08, 34.78), 5.0).center();
        assert!((center.latitude - 32.08).abs() < 1e-9);
        assert!((center.longitude - 34.78).abs() < 1e-9);
    }

    #[test]
    fn viewport_is_centered_and_scales_with_zoom() {
        let vp = Camera::new(loc(0.0, 0.0), 0.0).viewport(512.0, 512.0);
        assert!((vp.x_max - vp.x_min - CIRCUMFERENCE).abs() < 1e-3);
        assert!((vp.x_min + vp.x_max).abs() < 1e-6);
        assert!((vp.y_min + vp.y_max).abs() < 1e-6);
        let zoomed = Camera::new(loc(0.0, 0.0), 1.0).viewport(512.0, 512.0);
        assert!(((zoomed.x_max - zoomed.x_min) * 2.0 - CIRCUMFERENCE).abs() < 1e-3);
    }

    #[test]
    fn center_projects_to_screen_center() {
        for (bearing, pitch) in [(0.0, 0.0), (35.0, 0.0), (0.0, 45.0), (-120.0, 60.0)] {
            let camera = oriented(bearing, pitch);
            let p = camera.projection(800.0, 600.0);
            let (cx, cy) = camera.center_meters();
            let (sx, sy) = p.project(cx, cy).unwrap();
            assert!((sx - 400.0).abs() < 1e-6 && (sy - 300.0).abs() < 1e-6);
        }
    }

    #[test]
    fn unproject_inverts_project() {
        for (bearing, pitch) in [(0.0, 0.0), (35.0, 0.0), (0.0, 45.0), (-120.0, 60.0)] {
            let p = oriented(bearing, pitch).projection(800.0, 600.0);
            for (sx, sy) in [(100.0, 500.0), (700.0, 450.0), (400.0, 200.0)] {
                let (mx, my) = p.unproject(sx, sy);
                let (rx, ry) = p.project(mx, my).unwrap();
                assert!((rx - sx).abs() < 1e-6 && (ry - sy).abs() < 1e-6);
            }
        }
    }

    #[test]
    fn tilt_pulls_distant_points_towards_the_horizon() {
        let flat = oriented(0.0, 0.0).projection(800.0, 600.0);
        let tilted = oriented(0.0, 60.0).projection(800.0, 600.0);
        let (cx, cy) = (flat.center_x, flat.center_y);
        let north = cy + 100.0 * 1000.0;
        let (_, flat_y) = flat.project(cx, north).unwrap();
        let (_, tilted_y) = tilted.project(cx, north).unwrap();
        assert!(
            tilted_y > flat_y,
            "north should sit lower (nearer the horizon line) "
        );
        assert!(tilted_y < 300.0);
    }

    #[test]
    fn bearing_90_puts_east_at_the_top() {
        let p = oriented(90.0, 0.0).projection(800.0, 600.0);
        let (sx, sy) = p.project(p.center_x + 1000.0, p.center_y).unwrap();
        assert!((sx - 400.0).abs() < 1e-6);
        assert!(sy < 300.0);
    }

    #[test]
    fn zoom_keeps_anchor_fixed() {
        for (bearing, pitch) in [(0.0, 0.0), (50.0, 40.0)] {
            let mut camera = oriented(bearing, pitch);
            let (w, h, px, py) = (800.0, 600.0, 650.0, 420.0);
            let before = camera.projection(w, h).unproject(px, py);
            camera.zoom_by_resolution(0.5, px, py, w, h);
            assert!((camera.zoom - 5.0).abs() < 1e-9);
            let after = camera.projection(w, h).unproject(px, py);
            assert!((after.0 - before.0).abs() < 1e-6 && (after.1 - before.1).abs() < 1e-6);
        }
    }

    #[test]
    fn rotate_keeps_anchor_fixed() {
        let mut camera = oriented(10.0, 30.0);
        let (w, h, px, py) = (800.0, 600.0, 200.0, 450.0);
        let before = camera.projection(w, h).unproject(px, py);
        camera.rotate_by(25.0, px, py, w, h);
        assert!((camera.bearing - 35.0).abs() < 1e-9);
        let after = camera.projection(w, h).unproject(px, py);
        assert!((after.0 - before.0).abs() < 1e-6 && (after.1 - before.1).abs() < 1e-6);
    }

    #[test]
    fn pan_glues_the_dragged_point_to_the_pointer() {
        let mut camera = oriented(20.0, 45.0);
        let (w, h) = (800.0, 600.0);
        let grabbed = camera.projection(w, h).unproject(300.0, 400.0);
        camera.pan(60.0, -25.0, 360.0, 375.0, w, h);
        let (sx, sy) = camera
            .projection(w, h)
            .project(grabbed.0, grabbed.1)
            .unwrap();
        assert!((sx - 360.0).abs() < 1e-6 && (sy - 375.0).abs() < 1e-6);
    }

    #[test]
    fn pitch_is_clamped() {
        let mut camera = oriented(0.0, 0.0);
        camera.pitch_by(200.0);
        assert_eq!(camera.pitch, MAX_PITCH);
        camera.pitch_by(-500.0);
        assert_eq!(camera.pitch, 0.0);
    }

    #[test]
    fn viewport_round_trips_through_projection() {
        let camera = oriented(40.0, 30.0);
        let direct = camera.projection(800.0, 600.0);
        // Logical (half-size) screen: same view, different units.
        let from_vp = Projection::from_viewport(&camera.viewport(800.0, 600.0), 400.0, 300.0);
        let (mx, my) = direct.unproject(600.0, 450.0);
        let (sx, sy) = from_vp.project(mx, my).unwrap();
        assert!((sx - 300.0).abs() < 1e-6 && (sy - 225.0).abs() < 1e-6);
    }
}
