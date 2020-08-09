const express = require('express')
const axios = require('axios')
const Jimp = require('jimp')

const app = express()

const filterMap = {
	'watermark': async image => {
		const mark = await Jimp.read('./kodsport.png')
		mark.resize(900, 400)
		return await image.composite(mark, 25, 25);
	},
	'flip-180': async image => await image.rotate(180),
	'greyscale': async image => await image.greyscale(),
	'invert': async image => await image.invert(),
	'blur': async image => await image.blur(3)
}

app.get('/', (_, res) => {
	res.sendFile(__dirname + '/index.html')
})

app.get('/image/:filters/*', async (req, res) => {

	var filters = req.params.filters.split('|').filter(x => !!x)
	var imageUrl = req.params['0']

	if (imageUrl.includes('169.254.169.254')) {
		res.status(400).json({ error: 'HAHA! Så dum är jag inte!' })
		return
	}

	try {
		var resp = await axios.get(imageUrl, { responseType: 'arraybuffer' })
		var buffer = Buffer.from(resp.data, 'binary')
		var image = await Jimp.read(buffer)
	} catch (error) {
		if (!buffer && error.response) {
			var buffer = Buffer.from(error.response.data, 'binary')
		}
		res.status(500).json({ error: error.message, buffer })
		return
	}

	try {
		for (let i = 0; i < filters.length; i++) {
			if (!filterMap[filters[i]]) {
				res.status(400).json({ error: 'Filtret finns inte!' })
				return
			}
			image = await filterMap[filters[i]](image)
		}

		const mime = image.getMIME()
		image.getBuffer(mime, (_, buffer) => {
			res.set('Content-Type', mime)
			res.set('Cache-Control', 'max-age=10000000')
			res.send(buffer)
		})
	} catch (error) {
		res.status(500).json({ error })
		console.error(error)
	}

})

app.listen(8000)
