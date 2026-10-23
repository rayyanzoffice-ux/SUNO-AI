/// Chooses between the classifier that ships with the app (v1) and the model
/// trained by the SUNO v2 pipeline.
///
/// Keep this false until every Part A gate passes and the live tests in Part B
/// pass. Reverting v2 on demo day is this one line.
const bool useModelV2 = false;
