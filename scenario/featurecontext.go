package scenario

import (
	"github.com/cucumber/godog"
	"github.com/opencloud-eu/cs3api-validator/featurecontext"
	"github.com/opencloud-eu/cs3api-validator/steps/login"
	"github.com/opencloud-eu/cs3api-validator/steps/publicshare"
	"github.com/opencloud-eu/cs3api-validator/steps/resources"
	"github.com/opencloud-eu/cs3api-validator/steps/spaces"
)

// featureContext embeds all available feature contexts
type featureContext struct {
	*featurecontext.FeatureContext

	*login.LoginFeatureContext
	*publicshare.PublicShareFeatureContext
	*resources.ResourcesFeatureContext
	*spaces.SpacesFeatureContext
}

// newFeatureContext returns a new feature context for the scenario initialization
// and makes sure that all contexts have the same pointer to a single FeatureContext
func newFeatureContext(sc *godog.ScenarioContext) *featureContext {
	fc := &featurecontext.FeatureContext{}

	// every xxxFeatureContext needs to have the pointer to a _single_ / common FeatureContext
	uc := &featureContext{
		FeatureContext: fc,

		LoginFeatureContext:       login.NewLoginFeatureContext(fc, sc),
		PublicShareFeatureContext: publicshare.NewPublicShareFeatureContext(fc, sc),
		ResourcesFeatureContext:   resources.NewResourcesFeatureContext(fc, sc),
		SpacesFeatureContext:      spaces.NewSpacesFeatureContext(fc, sc),
	}
	return uc
}
