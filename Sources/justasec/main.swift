import Foundation

let app = JustasecApp()
guard app.validateSystemDependencies() else {
    fputs("justasec: dependency validation failed\n", stderr)
    exit(1)
}
fputs("justasec: ready\n", stderr)

dispatchMain()
