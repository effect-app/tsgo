// Package etscheckerhooks provides Effect diagnostics integration with TypeScript-Go.
// This package registers hooks into the checker to run Effect-specific diagnostics
// after each source file is type checked.
package etscheckerhooks

import (
	"context"

	"github.com/effect-ts/tsgo/etscore"
	"github.com/effect-ts/tsgo/internal/effectconfigraw"
	"github.com/effect-ts/tsgo/internal/rulerunner"
	"github.com/microsoft/typescript-go/shim/ast"
	"github.com/microsoft/typescript-go/shim/checker"
	"github.com/microsoft/typescript-go/shim/core"
)

// init registers the Effect diagnostics callbacks with TypeScript-Go.
func init() {
	// Set the version suffix so that core.Version() reports the effect-app build
	// as semver build metadata on the upstream 7.x base, e.g. "7.0.0-dev+effect-app.5".
	// Bump the build counter on each effect-app binary release (gz on effect-app/tsgo).
	core.SetVersionSuffix("+effect-app.8")
	effectconfigraw.Register()
	// Register the after check source file callback
	checker.RegisterAfterCheckSourceFileCallback(afterCheckSourceFile)
}

// getEffectConfig retrieves the Effect plugin configuration from the program's compiler options.
// Returns nil if no Effect config is present.
func getEffectConfig(p checker.Program) *etscore.EffectPluginOptions {
	return p.Options().Effect
}

// afterCheckSourceFile is called after type checking each source file.
// It runs Effect diagnostics if the plugin is enabled.
func afterCheckSourceFile(ctx context.Context, program checker.Program, c *checker.Checker, sf *ast.SourceFile) {
	diagnostics, err := rulerunner.Run(ctx, program, c, sf, getEffectConfig(program), nil)
	if err != nil {
		return
	}
	for _, diag := range diagnostics {
		c.AddDiagnostic(diag)
	}
}
