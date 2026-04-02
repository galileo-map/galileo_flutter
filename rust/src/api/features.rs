use crate::api::dart_types::{PolygonSymbol,Polygon};
use galileo::layer::feature_layer::symbol::SimplePolygonSymbol;
use galileo::galileo_types::cartesian::Point3;
use galileo::galileo_types::geo::impls::GeoPoint2d;
use galileo::render::render_bundle::RenderBundle;
use galileo::galileo_types::geometry::{Geometry,Geom};
use galileo::galileo_types::geo::Projection;
use galileo::galileo_types::geo::NewGeoPoint;
use galileo::galileo_types::impls::ClosedContour;

use galileo::layer::feature_layer::{Feature,symbol::Symbol};

impl Geometry for Polygon {
    type Point = GeoPoint2d;

    fn project<P: Projection<InPoint = Self::Point> + ?Sized>(
        &self,
        projection: &P,
    ) -> Option<Geom<P::OutPoint>> {

        let ring: Vec<GeoPoint2d> = self.points
            .iter()
            .map(|(lat, lon)| GeoPoint2d::latlon(*lat, *lon))
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

impl PolygonSymbol {
    fn get_polygon_symbol(&self, feature: &Polygon) -> SimplePolygonSymbol {
        let stroke_color = feature.style.strokeColor.to_galileo();
        let fill_color = feature.style.fillColor.to_galileo();
        let stroke_width = feature.style.strokeWidth;
        let stroke_offset = feature.style.strokeOffset;

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

