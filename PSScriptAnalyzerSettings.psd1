# PSScriptAnalyzer settings for scripts/check.ps1 and CI.
# Information-level suggestions are not enforced. Rules that conflict with a
# deliberate design are excluded here with the reason; one-off exceptions are
# suppressed in the code with a justification instead.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The bootstrap, scaffolder and gate are interactive console tools whose
        # status lines are meant for the person running them, not the pipeline.
        'PSAvoidUsingWriteHost'
    )
}
