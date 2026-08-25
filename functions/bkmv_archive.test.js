"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const AdmZip = require("adm-zip");

const {buildBkmvArchives} = require("./bkmv_archive");

test("places INI.TXT beside BKMVDATA.ZIP in the OPENFRMT tree", async () => {
  const generated = {
    exportDate: "20260825",
    exportTime: "1430",
    logicalExportPath: "OPENFRMT\\12345678.26\\08251430",
    iniBytes: Buffer.from("A000\r\n", "ascii"),
    bkmvBytes: Buffer.from("A100\r\nZ900\r\n", "ascii"),
  };
  const archives = await buildBkmvArchives({
    generated,
    exportTimestamp: new Date("2026-08-25T14:30:00+03:00"),
  });
  assert.equal(archives.outerZipFileName, "OPENFRMT_20260825_1430.zip");
  assert.equal(archives.bkmvZipFileName, "BKMVDATA.ZIP");

  const outer = new AdmZip(archives.outerZipBytes);
  assert.deepEqual(outer.getEntries().map((entry) => entry.entryName), [
    "OPENFRMT/12345678.26/08251430/INI.TXT",
    "OPENFRMT/12345678.26/08251430/BKMVDATA.ZIP",
  ]);
  assert.equal(
      outer.getEntry("OPENFRMT/12345678.26/08251430/BKMVDATA.TXT"),
      null,
  );
  const nestedBytes = outer
      .readFile("OPENFRMT/12345678.26/08251430/BKMVDATA.ZIP");
  const nested = new AdmZip(nestedBytes);
  assert.deepEqual(nested.getEntries().map((entry) => entry.entryName), [
    "BKMVDATA.TXT",
  ]);
  assert.equal(nested.readAsText("BKMVDATA.TXT"), "A100\r\nZ900\r\n");
});
