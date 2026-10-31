// Port of lib/src/util/graph.dart: `computeStrongComponents`, for a graph
// whose vertices are `0..vertex_count`.

/// Computes the strongly connected components of the graph whose vertices
/// are `0..vertex_count` and whose edges [neighbors_of] gives, in the order
/// upstream's Tarjan search finds them.
pub fn compute_strong_components(vertex_count: usize, neighbors_of: &dyn Fn(usize) -> Vec<usize>) -> Vec<Vec<usize>> {
    struct State<'a> {
        neighbors_of: &'a dyn Fn(usize) -> Vec<usize>,
        result: Vec<Vec<usize>>,
        count: usize,
        preorder_numbers: Vec<Option<usize>>,
        unassigned: Vec<usize>,
        candidates: Vec<usize>,
        assigned: Vec<bool>,
    }

    fn recursively_search(s: &mut State<'_>, vertex: usize) {
        s.preorder_numbers[vertex] = Some(s.count);
        s.count += 1;
        s.unassigned.push(vertex);
        s.candidates.push(vertex);
        for neighbor in (s.neighbors_of)(vertex) {
            match s.preorder_numbers[neighbor] {
                None => recursively_search(s, neighbor),
                Some(neighbor_preorder_number) => {
                    if !s.assigned[neighbor] {
                        while s.preorder_numbers[*s.candidates.last().unwrap()].unwrap() > neighbor_preorder_number {
                            s.candidates.pop();
                        }
                    }
                }
            }
        }
        if *s.candidates.last().unwrap() == vertex {
            let mut component = Vec::new();
            loop {
                let top = s.unassigned.pop().unwrap();
                component.push(top);
                s.assigned[top] = true;
                if top == vertex {
                    break;
                }
            }
            s.result.push(component);
            s.candidates.pop();
        }
    }

    let mut s = State {
        neighbors_of,
        result: Vec::new(),
        count: 0,
        preorder_numbers: vec![None; vertex_count],
        unassigned: Vec::new(),
        candidates: Vec::new(),
        assigned: vec![false; vertex_count],
    };
    for vertex in 0..vertex_count {
        if s.preorder_numbers[vertex].is_none() {
            recursively_search(&mut s, vertex);
        }
    }
    s.result
}
