const express = require("express");
const app = express();
const port = 8080;
const path = require('path');
const axios = require('axios');

// serve static content (index.html) using
// built-in middleware function in Express 
app.use(express.static('public'));
app.use(express.urlencoded({ extended: true }));

// this endpoint receives a URL in the post body
// and then makes a get request to that URL
// results are sent back to the caller
app.post('/callService', async (req, res) => {

    const url = req.body.url;
    let message = "";

    try {
        console.log("url: ", url);
        const response = await axios.get(url);
        message = response.data;

    } catch (error) {
        message = error.message;
        console.error(error.message);
    }

    res.send(`
        ${message}
        <p>
        </p>
    `);
});

app.listen(port, () => {
    console.log(`Example app listening on port ${port}`);
});