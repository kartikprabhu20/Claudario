enum MascotState {
    case idle
    case walking
    case controlled
    case playing
    /// On-screen mascot is hidden; a parallel mascot lives on the
    /// MacBook Touch Bar. Claude state arriving in this mode is
    /// buffered and replayed on exit, mirroring `.playing`.
    case touchBar
}
