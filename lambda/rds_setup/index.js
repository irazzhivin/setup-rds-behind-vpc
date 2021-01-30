const pg = require('pg'),
      AWS = require("aws-sdk");

const secretsmanager = require("aws-sdk/clients/secretsmanager");
const s3 = new AWS.S3();
const bucketName = process.env.BUCKET;
const queryCommandsKey = process.env.QUERY_COMMANDS_KEY;
const defregion = process.env.REGION;
const secret = process.env.SECRETID;
const rdsCertKey = process.env.RDS_CERT_KEY || "rds-cert.pem";
const getS3Object = async (bucket, key) => {
  var getParams = {
    Bucket: bucket,
    Key: key
  };
  return s3
    .getObject(getParams)
    .promise()
    .then(data => {
      return data.Body.toString("utf-8");
    });
};
exports.handler = async (event, context) => {
  const record = JSON.parse(event.Records[0].Sns.Message);
  console.log(record);
  let rdsCert;
  const promises = [
    getS3Object(bucketName, rdsCertKey),
    getS3Object(bucketName, queryCommandsKey)
  ];
  await Promise.all(promises).then(data => {
    console.info(data);
    rdsCert = data[0];
  });

  const secretsManagerClient = new secretsmanager({
    region: defregion,
  });
  const response = await secretsManagerClient
    .getSecretValue({
      SecretId: secret,
    })
    .promise();
  const secrets = JSON.parse(response.SecretString);


  var credentials = {
    user:     record.user,
    database: record.database,
    host:     record.host,
    port:     record.port,
    ssl:      {
      rejectUnauthorized: false,
      cert: rdsCert
    }
  };

  const pgClient = new pg.Client(credentials);
  //await pgClient.connect();
  for (const [key, value] of Object.entries(secrets)) {
    const exists = await pgClient.query(`SELECT 1 FROM pg_roles WHERE rolname='${key}'`);
    if (exists.rowCount === 0) {
      const results = await pgClient.query(`CREATE DATABASE db_${key}`);
      const results2 = await pgClient.query(`CREATE ROLE "${key}" WITH LOGIN PASSWORD '${value}';GRANT ALL PRIVILEGES ON DATABASE "db_${key}" TO "${key}";`);
      console.log(results);
      console.log(results2);
    }
    if (exists.rowCount === 1) {

      console.log(`User ${key} is already configured in this DB`);
    }
  }
  await pgClient.end();
};
