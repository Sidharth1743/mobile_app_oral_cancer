const imageInput = document.getElementById("imageInput");
const uploadForm = document.getElementById("uploadForm");
const analyzeButton = document.getElementById("analyzeButton");
const previewImage = document.getElementById("previewImage");
const emptyPreview = document.getElementById("emptyPreview");
const dropText = document.getElementById("dropText");
const modelStatus = document.getElementById("modelStatus");
const categoryBadge = document.getElementById("categoryBadge");
const recommendation = document.getElementById("recommendation");
const briefReason = document.getElementById("briefReason");
const disclaimer = document.getElementById("disclaimer");
const rawOutput = document.getElementById("rawOutput");
const errorBox = document.getElementById("errorBox");
const refreshStatus = document.getElementById("refreshStatus");
const adapterState = document.getElementById("adapterState");
const runtimeState = document.getElementById("runtimeState");
const deviceState = document.getElementById("deviceState");
const modelPath = document.getElementById("modelPath");
const fileList = document.getElementById("fileList");

let selectedFile = null;

function setError(message) {
  errorBox.hidden = false;
  errorBox.textContent = message;
}

function clearError() {
  errorBox.hidden = true;
  errorBox.textContent = "";
}

function setBadge(category) {
  categoryBadge.className = "badge";
  if (category === "refer_for_clinical_review") {
    categoryBadge.classList.add("refer");
    categoryBadge.textContent = "Refer";
  } else if (category === "low_risk_or_variation") {
    categoryBadge.classList.add("low");
    categoryBadge.textContent = "Low risk";
  } else {
    categoryBadge.classList.add("muted");
    categoryBadge.textContent = "No result";
  }
}

function setBusy(isBusy) {
  analyzeButton.disabled = isBusy || selectedFile === null;
  analyzeButton.textContent = isBusy ? "Analyzing" : "Analyze";
}

function fileSizeLabel(sizeBytes) {
  if (sizeBytes === null || sizeBytes === undefined) {
    return "Missing";
  }
  if (sizeBytes > 1024 * 1024 * 1024) {
    return `${(sizeBytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
  }
  if (sizeBytes > 1024 * 1024) {
    return `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${Math.max(1, Math.round(sizeBytes / 1024))} KB`;
}

function renderFiles(files) {
  fileList.innerHTML = "";
  Object.entries(files || {}).forEach(([name, file]) => {
    const row = document.createElement("div");
    row.className = "fileRow";

    const fileName = document.createElement("span");
    fileName.className = "fileName";
    fileName.textContent = name.replaceAll("_", " ");

    const fileState = document.createElement("span");
    fileState.className = "fileState";
    fileState.textContent = file.exists ? fileSizeLabel(file.size_bytes) : "Missing";

    const filePath = document.createElement("span");
    filePath.className = "filePath";
    filePath.textContent = file.path;

    row.append(fileName, fileState, filePath);
    fileList.append(row);
  });
}

async function loadStatus() {
  try {
    const response = await fetch("/api/status");
    const status = await response.json();
    const ready = status.ready === true;
    const loaded = status.model_loaded === true;
    const runtime = status.runtime || {};

    adapterState.textContent = ready ? "Files ready" : "Files missing";
    runtimeState.textContent = loaded ? "Loaded" : "Not loaded";
    deviceState.textContent = runtime.device || "CUDA unavailable";
    modelStatus.textContent = `${ready ? "Ready" : "Not ready"} | ${status.adapter_dir}`;
    modelPath.textContent = `Adapter: ${status.adapter_dir}`;
    renderFiles(status.files);
  } catch (error) {
    modelStatus.textContent = "Backend status unavailable";
    adapterState.textContent = "Unknown";
    runtimeState.textContent = "Unknown";
    deviceState.textContent = "Unknown";
    setError(error.message);
  }
}

imageInput.addEventListener("change", () => {
  clearError();
  selectedFile = imageInput.files[0] || null;
  analyzeButton.disabled = selectedFile === null;
  if (selectedFile === null) {
    previewImage.style.display = "none";
    previewImage.removeAttribute("src");
    emptyPreview.style.display = "grid";
    dropText.textContent = "Choose image";
    return;
  }

  previewImage.src = URL.createObjectURL(selectedFile);
  previewImage.style.display = "block";
  emptyPreview.style.display = "none";
  dropText.textContent = selectedFile.name;
  setBadge(null);
});

uploadForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  clearError();

  if (selectedFile === null) {
    setError("No image selected.");
    return;
  }

  setBusy(true);
  const formData = new FormData();
  formData.append("file", selectedFile);

  try {
    const response = await fetch("/api/analyze", {
      method: "POST",
      body: formData,
    });
    const payload = await response.json();

    if (!response.ok) {
      setError(`${payload.error || "Error"}: ${payload.message || payload.detail || "Request failed"}`);
      rawOutput.textContent = payload.message || payload.detail || "";
      return;
    }

    const result = payload.result;
    setBadge(result.category);
    recommendation.textContent = result.recommendation;
    briefReason.textContent = result.brief_reason;
    disclaimer.textContent = result.disclaimer;
    rawOutput.textContent = payload.raw_text;
    await loadStatus();
  } catch (error) {
    setError(error.message);
  } finally {
    setBusy(false);
  }
});

refreshStatus.addEventListener("click", loadStatus);

loadStatus();
