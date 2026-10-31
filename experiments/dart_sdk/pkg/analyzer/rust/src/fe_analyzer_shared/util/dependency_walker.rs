// Port of _fe_analyzer_shared's lib/src/util/dependency_walker.dart.
//
// It lives in this crate because the `_fe_analyzer_shared` crate was being
// changed by another port while this one was written; it belongs there.
//
// Upstream's nodes are objects that carry their Tarjan index, low link and
// cached dependencies; here a walker's nodes are numbered, the walker keeps
// those three for each number, and the class that walks (`Walk`) supplies
// what upstream's `Node` and `DependencyWalker` subclasses override.

/// What the subclasses of `DependencyWalker` and `Node` define.
pub trait Walk {
    /// `Node.isEvaluated`.
    fn is_evaluated(&self, node: usize) -> bool;
    /// `Node.computeDependencies`.
    fn compute_dependencies(&mut self, node: usize) -> Vec<usize>;
    /// `DependencyWalker.evaluate`.
    fn evaluate(&mut self, node: usize);
    /// `DependencyWalker.evaluateScc`.
    fn evaluate_scc(&mut self, scc: &[usize]);
}

/// The state upstream keeps in each `Node`: `_index`, `_lowLink` and
/// `_dependencies`.
#[derive(Default)]
pub struct DependencyWalker {
    index: Vec<u32>,
    low_link: Vec<u32>,
    dependencies: Vec<Option<Vec<usize>>>,
}

impl DependencyWalker {
    fn ensure(&mut self, node: usize) {
        if node >= self.index.len() {
            self.index.resize(node + 1, 0);
            self.low_link.resize(node + 1, 0);
            self.dependencies.resize(node + 1, None);
        }
    }

    /// `Node.getDependencies`.
    fn get_dependencies(&mut self, walk: &mut dyn Walk, node: usize) -> Vec<usize> {
        self.ensure(node);
        if let Some(d) = &self.dependencies[node] {
            return d.clone();
        }
        let d = walk.compute_dependencies(node);
        self.dependencies[node] = Some(d.clone());
        d
    }

    /// Walks the graph starting at [starting_point], evaluating every node
    /// it depends on first, and every strongly connected component as one.
    pub fn walk(&mut self, walk: &mut dyn Walk, starting_point: usize) {
        if walk.is_evaluated(starting_point) {
            return;
        }
        let mut index = 1;
        let mut stack = Vec::new();
        self.strong_connect(walk, starting_point, &mut index, &mut stack);
    }

    fn strong_connect(&mut self, walk: &mut dyn Walk, node: usize, index: &mut u32, stack: &mut Vec<usize>) {
        let mut has_trivial_cycle = false;

        self.ensure(node);
        self.index[node] = *index;
        self.low_link[node] = *index;
        *index += 1;
        stack.push(node);

        for dependency in self.get_dependencies(walk, node) {
            if walk.is_evaluated(dependency) {
                continue;
            }
            self.ensure(dependency);
            if node == dependency {
                has_trivial_cycle = true;
            } else if self.index[dependency] == 0 {
                self.strong_connect(walk, dependency, index, stack);
                if self.low_link[dependency] < self.low_link[node] {
                    self.low_link[node] = self.low_link[dependency];
                }
            } else if self.index[dependency] < self.low_link[node] {
                self.low_link[node] = self.index[dependency];
            }
        }

        if self.low_link[node] == self.index[node] {
            if *stack.last().unwrap() == node {
                stack.pop();
                if has_trivial_cycle {
                    walk.evaluate_scc(&[node]);
                } else {
                    walk.evaluate(node);
                }
            } else {
                let mut scc = Vec::new();
                loop {
                    let other = stack.pop().unwrap();
                    scc.push(other);
                    if other == node {
                        break;
                    }
                }
                walk.evaluate_scc(&scc);
            }
        }
    }
}
