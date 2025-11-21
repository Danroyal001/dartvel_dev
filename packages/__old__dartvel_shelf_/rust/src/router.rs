#[derive(Clone, Default)]
pub struct Route {
    pub kind: String,
    pub method: String,
    pub path: String,
    pub route_id: Option<u32>,
    pub flags: serde_json::Value,
    pub data: serde_json::Value,
}

#[derive(Default, Clone)]
pub struct Router {
    pub routes: Vec<Route>,
}

impl Router {
    pub fn new() -> Self {
        Self { routes: vec![] }
    }
    
    pub fn add(&mut self, r: Route) {
        self.routes.push(r);
    }

    pub fn find(&self, m: &str, p: &str) -> Option<&Route> {
        self.routes.iter().find(|r| r.method == m && r.path == p)
    }

    pub fn static_match(&self, p: &str) -> Option<&Route> {
        self.routes
            .iter()
            .find(|r| r.kind == "native" && r.method == "STATIC" && p.starts_with(&r.path))
    }
}
