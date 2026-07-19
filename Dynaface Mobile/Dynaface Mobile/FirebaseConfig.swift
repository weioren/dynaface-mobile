import Foundation

// MARK: - Firebase / GCP Configuration
//
// Replaces SupabaseConfig.swift. Unlike Supabase, Firebase doesn't need a
// hardcoded project URL + anon key here — that comes from
// `GoogleService-Info.plist` (added to the Xcode target) and is picked up
// automatically by `FirebaseApp.configure()` in DynafaceMobileApp.swift.
//
// What's still needed here is the small set of values Firebase can't infer:
// the two pre-existing GCS buckets the Dynaface worker already reads from /
// writes to (these predate Firebase being enabled on the project, so they
// aren't automatically the Firebase "default" bucket), and the URL of the
// `create_profile` Cloud Function used during signup (see Authentication.swift).
struct FirebaseConfig {

    /// Raw recordings bucket. Must match RAW_BUCKET / BUCKET_NAME used by
    /// google_remote_dynaface_worker.py and firestore_function.py.
    static let rawVideosBucketURL = "gs://dynaface-mobile-496023-dynaface-raw"

    /// Processed results bucket (annotated video, results.json, peak_frame.png).
    /// Must match RESULTS_BUCKET used by google_remote_dynaface_worker.py.
    static let resultsBucketURL = "gs://dynaface-mobile-496023-dynaface-results"

    /// HTTPS URL of the `create_profile` Cloud Function (see
    /// dynaface-mobile/gcp-backend/create_profile/main.py). Called once,
    /// right after Auth.auth().createUser(), to mint the app-side profile
    /// UUID and set the `app_uid` custom claim.
    static let createProfileFunctionURL = "https://us-east4-dynaface-mobile-496023.cloudfunctions.net/create_profile"

    /// HTTPS URL of the `delete_account` Cloud Function (see
    /// dynaface-mobile/gcp-backend/delete_account/main.py). Called from Profile
    /// after the user re-authenticates; erases all of their Firestore documents
    /// and Storage blobs, then the Firebase Auth user itself.
    static let deleteAccountFunctionURL = "https://us-east4-dynaface-mobile-496023.cloudfunctions.net/delete_account"
}
