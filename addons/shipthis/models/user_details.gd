## User details with optional fields

var has_accepted_terms = false
var source = ""
var terms_agreement_version_id = ""
var privacy_agreement_version_id = ""


func _init(
	has_accepted_terms: bool = false,
	source: String = "",
	terms_agreement_version_id: String = "",
	privacy_agreement_version_id: String = ""
) -> void:
	self.has_accepted_terms = has_accepted_terms
	self.source = source
	self.terms_agreement_version_id = terms_agreement_version_id
	self.privacy_agreement_version_id = privacy_agreement_version_id


func to_dict() -> Dictionary:
	var result = {}
	if has_accepted_terms:
		result["hasAcceptedTerms"] = has_accepted_terms
	if source != "":
		result["source"] = source
	if terms_agreement_version_id != "":
		result["termsAgreementVersionId"] = terms_agreement_version_id
	if privacy_agreement_version_id != "":
		result["privacyAgreementVersionId"] = privacy_agreement_version_id
	return result


static func from_dict(data: Dictionary):
	return load("res://addons/shipthis/models/user_details.gd").new(
		data.get("hasAcceptedTerms", false),
		data.get("source", ""),
		data.get("termsAgreementVersionId", ""),
		data.get("privacyAgreementVersionId", "")
	)

