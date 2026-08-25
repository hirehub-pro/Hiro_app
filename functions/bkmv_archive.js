"use strict";

const {PassThrough} = require("stream");
const {ZipArchive} = require("archiver");

function createZip(entries) {
  return new Promise((resolve, reject) => {
    const output = new PassThrough();
    const chunks = [];
    output.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
    output.on("end", () => resolve(Buffer.concat(chunks)));
    output.on("error", reject);

    const archive = new ZipArchive({zlib: {level: 9}});
    archive.on("warning", (error) => {
      if (error.code !== "ENOENT") reject(error);
    });
    archive.on("error", reject);
    archive.pipe(output);
    for (const entry of entries) {
      archive.append(Buffer.from(entry.bytes), {
        name: entry.name,
        date: entry.date,
        mode: 0o644,
      });
    }
    archive.finalize().catch(reject);
  });
}

async function buildBkmvArchives({generated, exportTimestamp}) {
  if (!generated?.bkmvBytes?.length || !generated?.iniBytes?.length) {
    throw new Error("INI.TXT and BKMVDATA.TXT bytes are required.");
  }
  const date = exportTimestamp instanceof Date ? exportTimestamp :
    new Date(exportTimestamp);
  if (Number.isNaN(date.getTime())) throw new Error("Invalid archive timestamp.");

  const bkmvZipBytes = await createZip([{
    name: "BKMVDATA.TXT",
    bytes: generated.bkmvBytes,
    date,
  }]);
  const relativeDirectory = generated.logicalExportPath.replaceAll("\\", "/");
  const outerZipBytes = await createZip([
    {
      name: `${relativeDirectory}/INI.TXT`,
      bytes: generated.iniBytes,
      date,
    },
    {
      name: `${relativeDirectory}/BKMVDATA.ZIP`,
      bytes: bkmvZipBytes,
      date,
    },
  ]);
  const stamp = `${generated.exportDate}_${generated.exportTime}`;
  return {
    bkmvZipBytes,
    outerZipBytes,
    bkmvZipFileName: "BKMVDATA.ZIP",
    outerZipFileName: `OPENFRMT_${stamp}.zip`,
  };
}

module.exports = {
  buildBkmvArchives,
  createZip,
};
