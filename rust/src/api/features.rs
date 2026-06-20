use crate::api::dart_types::{Point, PointSymbol, Polygon, PolygonSymbol};
use galileo::galileo_types::cartesian::Point3;
use galileo::galileo_types::geo::impls::GeoPoint2d;
use galileo::galileo_types::geo::NewGeoPoint;
use galileo::galileo_types::geo::Projection;
use galileo::galileo_types::geometry::{Geom, Geometry};
use galileo::galileo_types::impls::ClosedContour;
use galileo::layer::feature_layer::symbol::SimplePolygonSymbol;
use galileo::render::point_paint::PointPaint;
use galileo::render::render_bundle::RenderBundle;

use galileo::layer::feature_layer::{symbol::Symbol, Feature};

impl Geometry for Polygon {
    type Point = GeoPoint2d;

    fn project<P: Projection<InPoint = Self::Point> + ?Sized>(
        &self,
        projection: &P,
    ) -> Option<Geom<P::OutPoint>> {
        if self.points.len() < 3 {
            return None;
        }
        let ring: Vec<GeoPoint2d> = self
            .points
            .iter()
            .map(|point| GeoPoint2d::latlon(point.latitude, point.longitude))
            .collect();

        let polygon = galileo::galileo_types::impls::Polygon::<GeoPoint2d>::new(
            ClosedContour::new(ring),
            vec![],
        );

        polygon.project(projection)
    }
}

impl Feature for Polygon {
    type Geom = Self;

    fn geometry(&self) -> &Self::Geom {
        self
    }
}

impl Geometry for Point {
    type Point = GeoPoint2d;

    fn project<P: Projection<InPoint = Self::Point> + ?Sized>(
        &self,
        projection: &P,
    ) -> Option<Geom<P::OutPoint>> {
        let coordinate: GeoPoint2d =
            GeoPoint2d::latlon(self.coordinate.latitude, self.coordinate.longitude);
        coordinate.project(projection)
    }
}

impl Feature for Point {
    type Geom = Point;
    fn geometry(&self) -> &Self::Geom {
        self
    }
}

impl PolygonSymbol {
    fn get_polygon_symbol(&self, feature: &Polygon) -> SimplePolygonSymbol {
        let stroke_color = feature.style.stroke_color.to_galileo();
        let fill_color = feature.style.fill_color.to_galileo();
        let stroke_width = feature.style.stroke_width;
        let stroke_offset = feature.style.stroke_offset;

        SimplePolygonSymbol::new(fill_color)
            .with_stroke_color(stroke_color)
            .with_stroke_width(stroke_width)
            .with_stroke_offset(stroke_offset)
    }
}

impl Symbol<Polygon> for PolygonSymbol {
    fn render(
        &self,
        feature: &Polygon,
        geometry: &Geom<Point3>,
        min_resolution: f64,
        bundle: &mut RenderBundle,
    ) {
        self.get_polygon_symbol(feature)
            .render(&(), geometry, min_resolution, bundle)
    }
}

impl Symbol<Point> for PointSymbol {
    fn render(
        &self,
        feature: &Point,
        geometry: &Geom<Point3>,
        min_resolution: f64,
        bundle: &mut RenderBundle,
    ) {
        if let Geom::Point(point) = geometry {
            bundle.add_point(
                point,
                &PointPaint::circle(feature.style.fill_color.to_galileo(), feature.style.size),
                min_resolution,
            );
        }
    }
}
